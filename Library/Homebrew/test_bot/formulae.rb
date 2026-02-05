# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Homebrew
  module TestBot
    class Formulae < TestFormulae
      attr_writer :testing_formulae, :added_formulae, :deleted_formulae

      def initialize(tap:, git:, dry_run:, fail_fast:, verbose:, output_paths:)
        super(tap:, git:, dry_run:, fail_fast:, verbose:)

        @built_formulae = []
        @bottle_checksums = {}
        @bottle_output_path = output_paths[:bottle]
        @linkage_output_path = output_paths[:linkage]
        @skipped_or_failed_formulae_output_path = output_paths[:skipped_or_failed_formulae]
      end

      def run!(args:)
        test_header(:Formulae)

        verify_local_bottles

        with_env(HOMEBREW_DISABLE_LOAD_FORMULA: "1") do
          # Portable Ruby bottles are handled differently.
          next if testing_portable_ruby?

          # TODO: move to extend/os
          # rubocop:todo Homebrew/MoveToExtendOS
          bottle_specifier = if OS.linux?
            "{linux,ubuntu}"
          else
            "{macos-#{MacOS.version},#{MacOS.version}-#{Hardware::CPU.arch}}"
          end
          # rubocop:enable Homebrew/MoveToExtendOS
          download_artifacts_from_previous_run!("bottles{,_#{bottle_specifier}*}", dry_run: args.dry_run?)
        end
        @bottle_checksums.merge!(
          bottle_glob("*", artifact_cache, ".{json,tar.gz}", bottle_tag: "*").to_h do |bottle_file|
            [bottle_file.realpath, bottle_file.sha256]
          end,
        )

        # #run! modifies `@testing_formulae`, so we need to track this separately.
        @testing_formulae_count = @testing_formulae.count
        perform_bash_cleanup = @testing_formulae.include?("bash")
        @tested_formulae_count = 0

        sorted_formulae.each do |f|
          verify_local_bottles
          if testing_portable_ruby?
            portable_formula!(f)
          else
            formula!(f, args:)
          end
          puts
          next if @testing_formulae_count < 3

          progress_text = +"Test progress: "
          progress_text += "#{@tested_formulae_count} formula(e) tested, "
          progress_text += "#{@testing_formulae_count - @tested_formulae_count} remaining"
          info_header progress_text
        end

        @deleted_formulae.each do |f|
          deleted_formula!(f)
          verify_local_bottles
          puts
        end

        return unless GitHub::Actions.env_set?

        # Remove `bash` after it is tested, since leaving a broken `bash`
        # installation in the environment can cause issues with subsequent
        # GitHub Actions steps.
        test "brew", "uninstall", "--formula", "--force", "bash" if perform_bash_cleanup

        File.open(ENV.fetch("GITHUB_OUTPUT"), "a") do |f|
          f.puts "skipped_or_failed_formulae=#{@skipped_or_failed_formulae.join(",")}"
        end

        @skipped_or_failed_formulae_output_path.write(@skipped_or_failed_formulae.join(","))
      ensure
        verify_local_bottles
        FileUtils.rm_rf artifact_cache
      end

      private

      def tap_needed_taps(deps)
        deps.each { |d| d.to_formula.recursive_dependencies }
      rescue TapFormulaUnavailableError => e
        raise if e.tap.installed?

        e.tap.clear_cache
        safe_system "brew", "tap", e.tap.name
        retry
      end

      def install_ca_certificates_if_needed
        return if DevelopmentTools.ca_file_handles_most_https_certificates?

        test "brew", "install", "--formulae", "ca-certificates",
             env: { "HOMEBREW_DEVELOPER" => nil }
      end

      def setup_formulae_deps_instances(formula, formula_name, args:)
        conflicts = formula.conflicts
        formula_recursive_dependencies = formula.recursive_dependencies.map(&:to_formula)
        formula_recursive_dependencies.each do |dependency|
          conflicts += dependency.conflicts
        end

        # If we depend on a versioned formula, make sure to unlink any other
        # installed versions to make sure that we use the right one.
        versioned_dependencies = formula_recursive_dependencies.select(&:versioned_formula?)
        versioned_dependencies.each do |dependency|
          alternative_versions = dependency.versioned_formulae

          begin
            unversioned_name = dependency.name.sub(/@\d+(\.\d+)*$/, "")
            alternative_versions << Formula[unversioned_name]
          rescue FormulaUnavailableError
            nil
          end

          unneeded_alternative_versions = alternative_versions - formula_recursive_dependencies
          conflicts += unneeded_alternative_versions
        end

        unlink_formulae = conflicts.map(&:name)
        unlink_formulae.uniq.each do |name|
          unlink_formula = Formulary.factory(name)
          next unless unlink_formula.latest_version_installed?
          next unless unlink_formula.linked_keg.exist?

          test "brew", "unlink", name
        end

        info_header "Determining dependencies..."
        installed = Utils.safe_popen_read("brew", "list", "--formula", "--full-name").split("\n")
        dependencies =
          Utils.safe_popen_read("brew", "deps", "--formula",
                                "--include-build",
                                "--include-test",
                                "--full-name",
                                formula_name)
               .split("\n")
        installed_dependencies = installed & dependencies
        installed_dependencies.each do |name|
          link_formula = Formulary.factory(name)
          next if link_formula.keg_only?
          next if link_formula.linked_keg.exist?
          next if unlink_formulae.include?(name)

          test "brew", "link", name
        end

        dependencies -= installed
        @unchanged_dependencies = dependencies - @testing_formulae
        unless @unchanged_dependencies.empty?
          test "brew", "fetch", "--formulae", "--retry",
               *@unchanged_dependencies
        end

        changed_dependencies = dependencies - @unchanged_dependencies
        unless changed_dependencies.empty?
          test "brew", "fetch", "--formulae", "--retry", "--build-from-source",
               *changed_dependencies

          ignore_failures = !args.test_default_formula? && changed_dependencies.any? do |dep|
            !bottled?(Formulary.factory(dep), no_older_versions: true)
          end

          # Install changed dependencies as new bottles so we don't have
          # checksum problems. We have to install all `changed_dependencies`
          # in one `brew install` command to make sure they are installed in
          # the right order.
          test("brew", "install", "--formulae", "--build-from-source",
               named_args:      changed_dependencies,
               ignore_failures:)
          # Run postinstall on them because the tested formula might depend on
          # this step
          test "brew", "postinstall", named_args: changed_dependencies, ignore_failures:
        end

        runtime_or_test_dependencies =
          Utils.safe_popen_read("brew", "deps", "--formula", "--include-test", formula_name)
               .split("\n")
        build_dependencies = dependencies - runtime_or_test_dependencies
        @unchanged_build_dependencies = build_dependencies - @testing_formulae
      end

      def cleanup_bottle_etc_var(formula)
        # Restore etc/var files from bottle so dependents can use them.
        formula.install_etc_var
      end

      def verify_local_bottles
        # Portable Ruby bottles are handled differently.
        return if testing_portable_ruby?

        # Setting `HOMEBREW_DISABLE_LOAD_FORMULA` probably doesn't do anything here but let's set it just to be safe.
        with_env(HOMEBREW_DISABLE_LOAD_FORMULA: "1") do
          missing_bottles = @bottle_checksums.keys.reject do |bottle_path|
            next true if bottle_path.exist?

            what = (bottle_path.extname == ".json") ? "JSON" : "tarball"
            onoe "Missing bottle #{what}: #{bottle_path}"
            false
          end

          mismatched_checksums = @bottle_checksums.reject do |bottle_path, expected_sha256|
            next true unless bottle_path.exist?
            next true if (actual_sha256 = bottle_path.sha256) == expected_sha256

            onoe <<~ERROR
              Bottle checksum mismatch for #{bottle_path}!
                Expected: #{expected_sha256}
                Actual:   #{actual_sha256}
            ERROR
            false
          end

          unexpected_bottles = bottle_glob(
            "**/*", Pathname.pwd, ".{json,tar.gz}", bottle_tag: "*"
          ).reject do |local_bottle|
            next true if @bottle_checksums.key?(local_bottle.realpath)

            what = (local_bottle.extname == ".json") ? "JSON" : "tarball"
            onoe "Unexpected bottle #{what}: #{local_bottle}"
            false
          end

          return true if missing_bottles.blank? && mismatched_checksums.blank? && unexpected_bottles.blank?

          # Delete these files so we don't end up uploading them.
          files_to_delete = mismatched_checksums.keys + unexpected_bottles
          files_to_delete += files_to_delete.select(&:symlink?).map(&:realpath)
          FileUtils.rm_rf files_to_delete

          test "false" # ensure that `test-bot` exits with an error.

          false
        end
      end

      def bottle_reinstall_formula(formula, new_formula, args:)
        unless build_bottle?(formula, args:)
          @bottle_filename = nil
          return
        end

        root_url = args.root_url

        # GitHub Releases url
        root_url ||= if tap.present? && !tap.core_tap? && !args.test_default_formula?
          "#{tap.default_remote}/releases/download/#{formula.name}-#{formula.pkg_version}"
        end

        # This is needed where sparse files may be handled (bsdtar >=3.0).
        # We use gnu-tar with sparse files disabled when --only-json-tab is passed.
        #
        # TODO: move to extend/os
        # rubocop:todo Homebrew/MoveToExtendOS
        ENV["HOMEBREW_BOTTLE_SUDO_PURGE"] = "1" if OS.mac? && MacOS.version >= :catalina && !args.only_json_tab?
        # rubocop:enable Homebrew/MoveToExtendOS

        bottle_args = ["--verbose", "--json", formula.full_name]
        bottle_args << "--keep-old" if args.keep_old? && !new_formula
        bottle_args << "--skip-relocation" if args.skip_relocation?
        bottle_args << "--force-core-tap" if args.test_default_formula?
        bottle_args << "--root-url=#{root_url}" if root_url
        bottle_args << "--only-json-tab" if args.only_json_tab?

        verify_local_bottles
        test "brew", "bottle", *bottle_args
        bottle_step = steps.last

        if !bottle_step.passed? || !bottle_step.output?
          failed formula.full_name, "bottling failed" unless args.dry_run?
          return
        end

        @bottle_filename = Pathname.new(
          bottle_step.output
                    .gsub(%r{.*(\./\S+#{HOMEBREW_BOTTLES_EXTNAME_REGEX}).*}om, '\1'),
        )
        @bottle_json_filename = Pathname.new(
          @bottle_filename.to_s.gsub(/\.(\d+\.)?tar\.gz$/, ".json"),
        )

        @bottle_checksums[@bottle_filename.realpath] = @bottle_filename.sha256
        @bottle_checksums[@bottle_json_filename.realpath] = @bottle_json_filename.sha256

        @bottle_output_path.write(bottle_step.output, mode: "a")

        bottle_merge_args =
          ["--merge", "--write", "--no-commit", "--no-all-checks", @bottle_json_filename]
        bottle_merge_args << "--keep-old" if args.keep_old? && !new_formula

        test "brew", "bottle", *bottle_merge_args
        test "brew", "uninstall", "--formula", "--force", "--ignore-dependencies", formula.full_name

        @testing_formulae.delete(formula.name)

        unless @unchanged_build_dependencies.empty?
          test "brew", "uninstall", "--formulae", "--force", "--ignore-dependencies", *@unchanged_build_dependencies
          @unchanged_dependencies -= @unchanged_build_dependencies
        end

        verify_attestations = if formula.name == "gh"
          nil
        else
          ENV.fetch("HOMEBREW_VERIFY_ATTESTATIONS", nil)
        end
        test "brew", "install", "--only-dependencies", @bottle_filename,
             env: { "HOMEBREW_VERIFY_ATTESTATIONS" => verify_attestations }
        test "brew", "install", @bottle_filename,
             env: { "HOMEBREW_VERIFY_ATTESTATIONS" => verify_attestations }
      end

      def build_bottle?(formula, args:)
        # Build and runtime dependencies must be bottled on the current OS,
        # but accept an older compatible bottle for test dependencies.
        return false if formula.deps.any? do |dep|
          !bottled_or_built?(
            dep.to_formula,
            @built_formulae - @skipped_or_failed_formulae,
            no_older_versions: !dep.test?,
          )
        end

        !args.build_from_source?
      end

      def livecheck(formula)
        return unless formula.livecheck_defined?
        return if formula.livecheck.skip?

        livecheck_step = test "brew", "livecheck", "--autobump", "--formula",
                              "--json", "--full-name", formula.full_name

        return if livecheck_step.failed?
        return unless livecheck_step.output?

        livecheck_info = JSON.parse(livecheck_step.output)&.first

        if livecheck_info["status"] == "error"
          error_msg = if livecheck_info["messages"].present? && livecheck_info["messages"].length.positive?
            livecheck_info["messages"].join("\n")
          else
            # An error message should always be provided alongside an "error"
            # status but this is a failsafe
            "Error encountered (no message provided)"
          end

          if GitHub::Actions.env_set?
            puts GitHub::Actions::Annotation.new(
              :error,
              error_msg,
              title: "#{formula}: livecheck error",
              file:  formula.path.to_s.delete_prefix("#{repository}/"),
            )
          else
            onoe error_msg
          end
        end

        # `status` and `version` are mutually exclusive (the presence of one
        # indicates the absence of the other)
        return if livecheck_info["status"].present?

        return if livecheck_info["version"]["newer_than_upstream"] != true

        current_version = livecheck_info["version"]["current"]
        latest_version = livecheck_info["version"]["latest"]

        newer_than_upstream_msg = if current_version.present? && latest_version.present?
          "The formula version (#{current_version}) is newer than the " \
            "version from `brew livecheck` (#{latest_version})."
        else
          "The formula version is newer than the version from `brew livecheck`."
        end

        if GitHub::Actions.env_set?
          puts GitHub::Actions::Annotation.new(
            :warning,
            newer_than_upstream_msg,
            title: "#{formula}: Formula version newer than livecheck",
            file:  formula.path.to_s.delete_prefix("#{repository}/"),
          )
        else
          opoo newer_than_upstream_msg
        end
      end

      def formula!(formula_name, args:)
        cleanup_during!(@testing_formulae, args:)

        test_header(:Formulae, method: "formula!(#{formula_name})")

        formula = Formulary.factory(formula_name)
        if formula.disabled?
          skipped formula_name, "#{formula.full_name} has been disabled!"
          return
        end

        test "brew", "deps", "--tree", "--prune", "--annotate", "--include-build", "--include-test",
             named_args: formula_name

        deps_without_compatible_bottles = formula.deps.map(&:to_formula)
        deps_without_compatible_bottles.reject! do |dep|
          bottled_or_built?(dep, @built_formulae - @skipped_or_failed_formulae)
        end
        bottled_on_current_version = bottled?(formula, no_older_versions: true)

        if deps_without_compatible_bottles.present? && !bottled_on_current_version
          message = <<~EOS
            #{formula_name} has dependencies without compatible bottles:
              #{deps_without_compatible_bottles * "\n  "}
          EOS
          skipped formula_name, message
          return
        end

        new_formula = @added_formulae.include?(formula_name)
        ignore_failures = !args.test_default_formula? && !bottled_on_current_version && !new_formula

        deps = []
        reqs = []

        build_flag = if build_bottle?(formula, args:)
          "--build-bottle"
        else
          if GitHub::Actions.env_set?
            puts GitHub::Actions::Annotation.new(
              :warning,
              "#{formula} has unbottled dependencies, so a bottle will not be built.",
              title: "No bottle built for #{formula}!",
              file:  formula.path.to_s.delete_prefix("#{repository}/"),
            )
          else
            onoe "Not building a bottle for #{formula} because it has unbottled dependencies."
          end

          skipped formula_name, "No bottle built."
          return
        end

        # Online checks are a bit flaky and less useful for PRs that modify multiple formulae.
        skip_online_checks = args.skip_online_checks? || (@testing_formulae_count > 5)

        fetch_args = [formula_name]
        fetch_args << build_flag
        fetch_args << "--force" if cleanup?(args)

        audit_args = [formula_name]
        audit_args << "--online" unless skip_online_checks
        if new_formula
          if !args.skip_new?
            audit_args << "--new"
          elsif !args.skip_new_strict?
            audit_args << "--strict"
          end
        else
          audit_args << "--git" << "--skip-style"
          audit_args << "--except=unconfirmed_checksum_change" if args.skip_checksum_only_audit?
          audit_args << "--except=stable_version" if args.skip_stable_version_audit?
          audit_args << "--except=revision" if args.skip_revision_audit?
        end

        # This needs to be done before any network operation.
        install_ca_certificates_if_needed

        if (messages = unsatisfied_requirements_messages(formula))
          test "brew", "fetch", "--formula", "--retry", *fetch_args
          test "brew", "audit", "--formula", *audit_args

          skipped formula_name, messages
          return
        end

        deps |= formula.deps.to_a.reject(&:optional?)
        reqs |= formula.requirements.to_a.reject(&:optional?)

        tap_needed_taps(deps)
        install_curl_if_needed(formula)
        install_mercurial_if_needed(deps, reqs)
        install_subversion_if_needed(deps, reqs)
        setup_formulae_deps_instances(formula, formula_name, args:)

        test "brew", "uninstall", "--formula", "--force", formula_name if formula.latest_version_installed?

        install_args = ["--verbose", "--formula"]
        install_args << build_flag

        # We can't verify attestations if we're building `gh`.
        verify_attestations = if formula_name == "gh"
          nil
        else
          ENV.fetch("HOMEBREW_VERIFY_ATTESTATIONS", nil)
        end
        # Don't care about e.g. bottle failures for dependencies.
        test "brew", "install", "--only-dependencies", *install_args, formula_name,
             env: { "HOMEBREW_DEVELOPER"           => nil,
                    "HOMEBREW_VERIFY_ATTESTATIONS" => verify_attestations }

        info_header "Starting tests for #{formula_name}"

        test "brew", "fetch", "--formula", "--retry", *fetch_args

        env = {}
        env["HOMEBREW_GIT_PATH"] = nil if deps.any? do |d|
          d.name == "git" && (!d.test? || d.build?)
        end

        install_step_passed = formula_installed_from_bottle =
          artifact_cache_valid?(formula) &&
          verify_local_bottles && # Checking the artifact cache loads formulae, so do this check second.
          install_formula_from_bottle!(formula_name,
                                       bottle_dir:                  artifact_cache,
                                       testing_formulae_dependents: false,
                                       dry_run:                     args.dry_run?)

        install_step_passed ||= begin
          test("brew", "install", *install_args,
               named_args:      formula_name,
               env:             env.merge({ "HOMEBREW_DEVELOPER"           => nil,
                                            "HOMEBREW_VERIFY_ATTESTATIONS" => verify_attestations }),
               ignore_failures:, report_analytics: true)
          steps.last.passed?
        end

        livecheck(formula) if !args.skip_livecheck? && !skip_online_checks

        test "brew", "style", "--formula", formula_name, report_analytics: true
        test "brew", "audit", "--formula", *audit_args, report_analytics: true unless formula.deprecated?
        unless install_step_passed
          if ignore_failures
            skipped formula_name, "install failed"
          else
            failed formula_name, "install failed"
          end

          return
        end

        if formula_installed_from_bottle
          moved_artifacts = bottle_glob(formula_name, artifact_cache, ".{json,tar.gz}").map(&:realpath)
          Pathname.pwd.install moved_artifacts

          moved_artifacts.each do |old_location|
            new_location = old_location.basename.realpath
            @bottle_checksums[new_location] = @bottle_checksums.fetch(old_location)
            @bottle_checksums.delete(old_location)
          end
        else
          bottle_reinstall_formula(formula, new_formula, args:)
        end
        @built_formulae << formula.full_name
        test("brew", "linkage", "--test", named_args: formula_name, ignore_failures:, report_analytics: true)
        failed_linkage_or_test_messages ||= []
        failed_linkage_or_test_messages << "linkage failed" unless steps.last.passed?

        if steps.last.passed?
          # Check for opportunistic linkage. Ignore failures because
          # they can be unavoidable but we still want to know about them.
          test "brew", "linkage", "--cached", "--test", "--strict",
               named_args:      formula_name,
               ignore_failures: !args.test_default_formula?
        end

        test "brew", "linkage", "--cached", formula_name
        @linkage_output_path.write(Formatter.headline(steps.last.command_trimmed, color: :blue), mode: "a")
        @linkage_output_path.write("\n", mode: "a")
        @linkage_output_path.write(steps.last.output, mode: "a")

        test "brew", "install", "--formula", "--only-dependencies", "--include-test", formula_name

        if formula.test_defined?
          env = {}
          env["HOMEBREW_GIT_PATH"] = nil if deps.any? do |d|
            d.name == "git" && (!d.build? || d.test?)
          end

          # Intentionally not passing --retry here to avoid papering over
          # flaky tests when a formula isn't being pulled in as a dependent.
          test("brew", "test", "--verbose", named_args: formula_name, env:, ignore_failures:,
report_analytics: true)
          failed_linkage_or_test_messages << "test failed" unless steps.last.passed?
        end

        # Move bottle and don't test dependents if the formula linkage or test failed.
        if failed_linkage_or_test_messages.present?
          if @bottle_filename
            failed_dir = @bottle_filename.dirname/"failed"
            moved_artifacts = [@bottle_filename, @bottle_json_filename].map(&:realpath)
            failed_dir.install moved_artifacts

            moved_artifacts.each do |old_location|
              new_location = (failed_dir/old_location.basename).realpath
              @bottle_checksums[new_location] = @bottle_checksums.fetch(old_location)
              @bottle_checksums.delete(old_location)
            end
          end

          if ignore_failures
            skipped formula_name, failed_linkage_or_test_messages.join(", ")
          else
            failed formula_name, failed_linkage_or_test_messages.join(", ")
          end
        end
      ensure
        @tested_formulae_count += 1
        cleanup_bottle_etc_var(formula) if cleanup?(args)

        if @unchanged_dependencies.present?
          test "brew", "uninstall", "--formulae", "--force", "--ignore-dependencies", *@unchanged_dependencies
        end
      end

      def portable_formula!(formula_name)
        test_header(:Formulae, method: "portable_formula!(#{formula_name})")

        install_ca_certificates_if_needed

        # Can't resolve attestations properly on old macOS versions.
        ENV["HOMEBREW_NO_VERIFY_ATTESTATIONS"] = "1"

        # On Linux, install glibc and linux-headers from bottles and don't install their build dependencies.
        bottled_dep_allowlist = /\A(?:glibc|linux-headers)@/
        deps = Dependency.expand(Formula[formula_name],
                                 cache_key: "portable-package-#{formula_name}") do |_dependent, dep|
          Dependency.prune if dep.test? || dep.optional?

          next unless bottled_dep_allowlist.match?(dep.name)

          Dependency.keep_but_prune_recursive_deps
        end.map(&:name)

        bottled_deps, deps = deps.partition { |dep| bottled_dep_allowlist.match?(dep) }

        # Install bottled dependencies.
        test "brew", "install", *bottled_deps if bottled_deps.present?

        # Build bottles for all other dependencies.
        test "brew", "install", "--build-bottle", *deps

        # Build main bottle.
        test "brew", "install", "--build-bottle", formula_name
        test "brew", "uninstall", "--force", "--ignore-dependencies", *deps
        test "brew", "test", formula_name
        test "brew", "linkage", formula_name
        test "brew", "bottle", "--skip-relocation", "--json", "--no-rebuild", formula_name
      end

      def deleted_formula!(formula_name)
        test_header(:Formulae, method: "deleted_formula!(#{formula_name})")

        test "brew", "uses",
             "--formula",
             "--eval-all",
             "--include-build",
             "--include-optional",
             "--include-test",
             formula_name
      end

      def testing_portable_ruby?
        tap&.core_tap? && @testing_formulae.include?("portable-ruby")
      end
    end
  end
end
