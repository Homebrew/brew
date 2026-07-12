# typed: strict
# frozen_string_literal: true

module Homebrew
  module TestBot
    class Formulae < TestFormulae
      sig { params(testing_formulae: T::Array[String]).void }
      attr_writer :testing_formulae

      sig { params(added_formulae: T::Array[String]).void }
      attr_writer :added_formulae

      sig { params(deleted_formulae: T::Array[String]).void }
      attr_writer :deleted_formulae

      sig {
        params(
          tap:          T.nilable(Tap),
          git:          String,
          dry_run:      T::Boolean,
          fail_fast:    T::Boolean,
          verbose:      T::Boolean,
          output_paths: T::Hash[Symbol, Pathname],
        ).void
      }
      def initialize(tap:, git:, dry_run:, fail_fast:, verbose:, output_paths:)
        super(tap:, git:, dry_run:, fail_fast:, verbose:)

        @built_formulae = T.let([], T::Array[String])
        @bottle_checksums = T.let({}, T::Hash[Pathname, String])
        @bottle_output_path = T.let(output_paths.fetch(:bottle), Pathname)
        @linkage_output_path = T.let(output_paths.fetch(:linkage), Pathname)
        @skipped_or_failed_formulae_output_path = T.let(output_paths.fetch(:skipped_or_failed_formulae), Pathname)
        @testing_formulae = T.let([], T::Array[String])
        @added_formulae = T.let([], T::Array[String])
        @deleted_formulae = T.let([], T::Array[String])
        @testing_formulae_count = T.let(0, Integer)
        @tested_formulae_count = T.let(0, Integer)
        @unchanged_dependencies = T.let([], T::Array[String])
        @unchanged_build_dependencies = T.let([], T::Array[String])
        @bottle_filename = T.let(nil, T.nilable(Pathname))
        @bottle_json_filename = T.let(nil, T.nilable(Pathname))
      end

      sig { params(args: Homebrew::Cmd::TestBotCmd::Args).void }
      def run!(args:)
        test_header(:Formulae)

        verify_local_bottles

        with_env(HOMEBREW_DISABLE_LOAD_FORMULA: "1") do
          # Portable Ruby bottles are handled differently.
          next if testing_portable_ruby?

          download_artifacts_from_previous_run!("bottles{,_#{previous_run_artifact_specifier}*}",
                                                dry_run: args.dry_run?)
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
            portable_formula!(f, args:)
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

      sig { void }
      def install_ca_certificates_if_needed
        return if DevelopmentTools.ca_file_handles_most_https_certificates?

        test "brew", "install", "--formulae", "ca-certificates",
             env: { "HOMEBREW_DEVELOPER" => nil }
      end

      sig { params(formula: Formula, formula_name: String, args: Homebrew::Cmd::TestBotCmd::Args).void }
      def setup_formulae_deps_instances(formula, formula_name, args:)
        conflicts = T.let(formula.conflicts, T::Array[T.any(Formula, Formula::FormulaConflict)])
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

      sig { params(formula: Formula).void }
      def cleanup_bottle_etc_var(formula)
        # Restore bottled `etc`/`var` through `Formula#install_etc_var`, keeping
        # test-bot cleanup aligned with `InstallRenamed` config handling.
        formula.install_etc_var
      end

      sig { returns(T::Boolean) }
      def verify_local_bottles
        # Portable Ruby bottles are handled differently.
        return false if testing_portable_ruby?

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

      sig { params(formula: Formula, new_formula: T.nilable(T::Boolean), args: Homebrew::Cmd::TestBotCmd::Args).void }
      def bottle_reinstall_formula(formula, new_formula, args:)
        unless build_bottle?(formula, args:)
          @bottle_filename = T.let(nil, T.nilable(Pathname))
          return
        end

        root_url = args.root_url

        # GitHub Releases url
        root_url ||= if tap.present? && !T.must(tap).core_tap? && !args.test_default_formula?
          "#{T.must(tap).default_remote}/releases/download/#{formula.name}-#{formula.pkg_version}"
        end

        setup_bottle_sudo_purge!(args:)

        bottle_args = ["--verbose", "--json", formula.full_name]
        bottle_args << "--keep-old" if args.keep_old? && !new_formula
        bottle_args << "--skip-relocation" if args.skip_relocation?
        bottle_args << "--force-core-tap" if args.test_default_formula?
        bottle_args << "--root-url=#{root_url}" if root_url
        bottle_args << "--only-json-tab" if args.only_json_tab?

        verify_local_bottles
        test "brew", "bottle", *bottle_args
        bottle_step = steps.fetch(-1)

        if !bottle_step.passed? || !bottle_step.output?
          failed formula.full_name, "bottling failed" unless args.dry_run?
          return
        end

        @bottle_filename = Pathname.new(
          T.must(bottle_step.output)
           .gsub(%r{.*(\./\S+#{HOMEBREW_BOTTLES_EXTNAME_REGEX}).*}om, '\1'),
        )
        @bottle_json_filename = Pathname.new(
          @bottle_filename.to_s.gsub(/\.(\d+\.)?tar\.gz$/, ".json"),
        )

        @bottle_checksums[@bottle_filename.realpath] = @bottle_filename.sha256
        @bottle_checksums[@bottle_json_filename.realpath] = @bottle_json_filename.sha256

        @bottle_output_path.write(bottle_step.output, mode: "a")

        bottle_merge_args =
          ["--merge", "--write", "--no-commit", "--no-all-checks", @bottle_json_filename.to_s]
        bottle_merge_args << "--keep-old" if args.keep_old? && !new_formula

        test "brew", "bottle", *bottle_merge_args
        annotate_missing_all_bottle(formula) if steps.fetch(-1).passed?
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
        test "brew", "install", "--only-dependencies", @bottle_filename.to_s,
             env: { "HOMEBREW_VERIFY_ATTESTATIONS" => verify_attestations }
        test "brew", "install", @bottle_filename.to_s,
             env: { "HOMEBREW_VERIFY_ATTESTATIONS" => verify_attestations }
      end

      sig { params(formula: Formula, args: Homebrew::Cmd::TestBotCmd::Args).returns(T::Boolean) }
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

      sig { params(args: Homebrew::Cmd::TestBotCmd::Args).void }
      def setup_bottle_sudo_purge!(args:); end

      sig { params(dependency: Dependency, dependency_name: String).returns(T::Boolean) }
      def dependency_name_match?(dependency, dependency_name)
        return true if dependency.name == dependency_name
        return false if Utils.tap_from_full_name(dependency.name).present?
        return false if Utils.tap_from_full_name(dependency_name).present?

        Utils.name_from_full_name(dependency.name) == Utils.name_from_full_name(dependency_name)
      end

      sig { params(_formula: Formula, dependencies: T::Array[Dependency]).returns(T::Array[String]) }
      def recursive_runtime_dependency_names(_formula, dependencies)
        dependencies.each_with_object(Set.new) do |dep, set|
          dep_f = dep.to_formula
          set.add(dep_f.full_name)
          set.merge(dep_f.runtime_dependencies(read_from_tab: false, undeclared: false).map(&:name))
        end.to_a
      end

      sig { params(formula: Formula).void }
      def annotate_added_dependencies(formula)
        return unless GitHub::Actions.env_set?
        return if @added_formulae.include?(formula.name)
        return if (git = self.git).nil?

        direct_runtime_dependencies = formula.deps.reject do |dependency|
          dependency.build? || dependency.optional? || dependency.test?
        end

        new_line = T.let(nil, T.nilable(Integer))
        Utils.safe_popen_read(
          git, "-C", repository, "diff", "--no-ext-diff", "--unified=0", "origin/HEAD", "HEAD", "--",
          formula.path.relative_path_from(repository).to_s
        ).each_line do |diff_line|
          if (match = diff_line.match(/^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/))
            new_line = match[1]&.to_i
            next
          end

          line = new_line
          next if line.nil?

          if diff_line.start_with?("+") && !diff_line.start_with?("+++")
            dependency_name = diff_line[/^\+\s*depends_on\s+["']([^"']+)["']/, 1]
            new_line = line + 1
          elsif !diff_line.start_with?("-") || diff_line.start_with?("---")
            new_line = line + 1
            next
          else
            next
          end
          next if dependency_name.blank?

          dependency = direct_runtime_dependencies.find do |runtime_dependency|
            dependency_name_match?(runtime_dependency, dependency_name)
          end
          next if dependency.nil?

          dependency_formula = dependency.to_formula
          existing_runtime_dependency_names = recursive_runtime_dependency_names(
            formula,
            direct_runtime_dependencies.reject do |runtime_dependency|
              dependency_name_match?(runtime_dependency, dependency.name)
            end,
          )
          new_recursive_dependency_names =
            (
              [dependency_formula.full_name] +
              recursive_runtime_dependency_names(
                dependency_formula,
                dependency_formula.runtime_dependencies(read_from_tab: false, undeclared: false),
              )
            ).uniq - existing_runtime_dependency_names
          next if new_recursive_dependency_names.blank?

          sizes = new_recursive_dependency_names.map do |formula_name|
            installed_sizes = @dependency_impact_installed_sizes ||=
              T.let({}, T.nilable(T::Hash[String, T.nilable(Integer)]))
            next installed_sizes[formula_name] if installed_sizes.key?(formula_name)

            installed_sizes[formula_name] =
              if (bottle = Formulary.factory(formula_name).bottle_for_tag(Utils::Bottles.tag))
                bottle.fetch_tab(quiet: true)
                bottle.installed_size
              end
          rescue DownloadError, FormulaUnavailableError, Resource::BottleManifest::Error
            nil
          end
          dependency_count = new_recursive_dependency_names.count
          message = "Adding `#{dependency_name}` adds #{dependency_count} new recursive " \
                    "#{Utils.pluralize("dependency", dependency_count)} " \
                    "on #{Utils::Bottles.tag} (#{Formatter.disk_usage_readable(sizes.compact.sum)}"
          unknown_size_count = sizes.count(&:nil?)
          message << ", plus #{Utils.pluralize("unknown size", unknown_size_count, include_count: true)}" \
            if unknown_size_count.positive?
          puts GitHub::Actions::Annotation.new(
            :warning,
            "#{message}).",
            file:  formula.path.to_s.delete_prefix("#{repository}/"),
            line:,
            title: "#{formula}: new dependency impact",
          )
        end
      rescue => e
        opoo "Failed to determine dependency impact for #{formula.full_name}: #{e}"
      end

      sig { params(formula: Formula, bottle_dir: Pathname).void }
      def annotate_missing_all_bottle(formula, bottle_dir: Pathname.pwd)
        return unless formula.bottle_specification.tag?(Utils::Bottles.tag(:all))

        require "utils/ast"

        bottle_tag = Utils::Bottles.tag
        bottle_sha256_node_tag = lambda do |sha256_node, tag|
          sha256_node.arguments.grep(RuboCop::AST::HashNode).any? do |hash_node|
            hash_node.pairs.any? do |pair|
              Utils::AST.literal_value(pair.key) == tag ||
                Utils::AST.literal_value(pair.value) == tag
            end
          end
        end
        bottle_node = Utils::AST::FormulaAST.new(formula.path.read).bottle_block
        sha256_nodes = Utils::AST.body_children(
          bottle_node.is_a?(RuboCop::AST::BlockNode) ? bottle_node.body : nil,
        ).filter_map do |node|
          next unless node.is_a?(RuboCop::AST::SendNode)
          next if node.method_name != :sha256

          node
        end
        return if sha256_nodes.any? { |sha256_node| bottle_sha256_node_tag.call(sha256_node, :all) }

        # This predictor only has local JSONs, so mirror the merge-time tag count
        # and cellar/checksum dedupe gates; final merge handles version/rebuild.
        local_tag_hashes = local_bottle_tag_hashes(formula.name, bottle_dir:)
        return if local_tag_hashes.key?("all")
        return if local_tag_hashes.count < 2
        return if local_tag_hashes.values.uniq { |tag_hash| [tag_hash["cellar"], tag_hash["sha256"]] }.one?

        tag_hash = local_tag_hashes[bottle_tag.to_s]
        line = sha256_nodes.find do |sha256_node|
          bottle_sha256_node_tag.call(sha256_node, bottle_tag.to_sym)
        end&.source_range&.line
        bottle_details = if tag_hash.present?
          " (cellar `#{tag_hash["cellar"]}`, sha256 `#{tag_hash["sha256"]}`)"
        else
          ""
        end
        message = "This formula had an `:all` bottle but the #{bottle_tag} test-bot bottle is " \
                  "platform-specific#{bottle_details}. If the final bottle merge cannot create a new " \
                  "`:all` bottle, expect #{Utils::Bottles.missing_all_bottle_publish_note}; this is for " \
                  "information only and should not block merge."

        if GitHub::Actions.env_set?
          puts GitHub::Actions::Annotation.new(
            :warning,
            message,
            file:  formula.path.to_s.delete_prefix("#{repository}/"),
            line:,
            title: "#{formula}: missing :all bottle",
          )
        else
          opoo message
        end
      rescue => e
        opoo "Failed to determine missing `:all` bottle impact for #{formula.full_name}: #{e}"
      end

      sig {
        params(formula_name: String, bottle_dir: Pathname)
          .returns(T::Hash[String, T::Hash[String, T.anything]])
      }
      def local_bottle_tag_hashes(formula_name, bottle_dir:)
        tag_hashes = T.let({}, T::Hash[String, T::Hash[String, T.anything]])
        bottle_glob(formula_name, bottle_dir, ".json", bottle_tag: "*").each do |local_bottle_json|
          bottle_hash = JSON.parse(local_bottle_json.read).dig(formula_name, "bottle")
          next unless bottle_hash.is_a?(Hash)

          cellar = bottle_hash["cellar"]
          tags = bottle_hash["tags"]
          next unless tags.is_a?(Hash)

          tags.each do |tag, tag_hash|
            next if !tag.is_a?(String) || !tag_hash.is_a?(Hash)

            tag_hashes[tag] = tag_hash.merge("cellar" => tag_hash["cellar"] || cellar)
          end
        end
        tag_hashes
      end

      sig { params(formula: Formula).void }
      def livecheck(formula)
        return unless formula.livecheck_defined?
        return if formula.livecheck.skip?

        livecheck_step = test "brew", "livecheck", "--autobump", "--formula",
                              "--json", "--full-name", formula.full_name

        return if livecheck_step.failed?
        return unless livecheck_step.output?

        livecheck_info = JSON.parse(T.must(livecheck_step.output)).first

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

      sig { params(formula_name: String, args: Homebrew::Cmd::TestBotCmd::Args).void }
      def formula!(formula_name, args:)
        cleanup_during!(@testing_formulae, args:)

        test_header(:Formulae, method: "formula!(#{formula_name})")

        formula = Formulary.factory(formula_name)
        begin
          if formula.disabled?
            skipped formula_name, "#{formula.full_name} has been disabled!"
            return
          end

          new_formula = @added_formulae.include?(formula_name)
          annotate_added_dependencies(formula) unless new_formula

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
            steps.fetch(-1).passed?
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
          failed_linkage_or_test_messages << "linkage failed" unless steps.fetch(-1).passed?

          if steps.fetch(-1).passed?
            # Check for opportunistic linkage. Ignore failures because
            # they can be unavoidable but we still want to know about them.
            test "brew", "linkage", "--cached", "--test", "--strict",
                 named_args:      formula_name,
                 ignore_failures: !args.test_default_formula?
          end

          test "brew", "linkage", "--cached", formula_name
          @linkage_output_path.write(Formatter.headline(steps.fetch(-1).command_trimmed, color: :blue), mode: "a")
          @linkage_output_path.write("\n", mode: "a")
          @linkage_output_path.write(steps.fetch(-1).output, mode: "a")

          test "brew", "install", "--formula", "--only-dependencies", "--include-test", formula_name

          if formula.test_defined?
            env = {}
            env["HOMEBREW_GIT_PATH"] = nil if deps.any? do |d|
              d.name == "git" && (!d.build? || d.test?)
            end

            # Intentionally not passing --retry here to avoid papering over
            # flaky tests when a formula isn't being pulled in as a dependent.
            test(
              "brew", "test", "--verbose", named_args: formula_name, env:, ignore_failures:, report_analytics: true
            )
            failed_linkage_or_test_messages << "test failed" unless steps.fetch(-1).passed?
          end

          # Move bottle and don't test dependents if the formula linkage or test failed.
          if failed_linkage_or_test_messages.present?
            if @bottle_filename
              failed_dir = @bottle_filename.dirname/"failed"
              moved_artifacts = [@bottle_filename, T.must(@bottle_json_filename)].map(&:realpath)
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
      end

      sig { params(formula_name: String, args: Homebrew::Cmd::TestBotCmd::Args).void }
      def portable_formula!(formula_name, args:)
        test_header(:Formulae, method: "portable_formula!(#{formula_name})")

        install_ca_certificates_if_needed

        # Can't resolve attestations properly on old macOS versions.
        ENV["HOMEBREW_NO_VERIFY_ATTESTATIONS"] = "1"

        # On Linux, install glibc and linux-headers from bottles and don't install their build dependencies.
        bottled_dep_allowlist = /\A(?:glibc|linux-headers)@/
        deps = Dependency.expand(Formula[formula_name],
                                 cache_key: "portable-package-#{formula_name}") do |_dependent, dep|
          next Dependable::PRUNE if dep.test? || dep.optional?

          next unless bottled_dep_allowlist.match?(dep.name)

          next Dependable::KEEP_BUT_PRUNE_RECURSIVE_DEPS
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

        # We only do full testing on `portable-ruby` itself.
        return if formula_name != "portable-ruby"
        return if args.dry_run?

        bottle_file = bottle_glob(formula_name).first
        if bottle_file.nil?
          failed formula_name, "no bottle file found for portable-ruby validation"
          return
        end

        filename = bottle_file.basename.to_s
        _, tag_string, = Utils::Bottles.extname_tag_rebuild(filename)
        if tag_string.blank?
          failed formula_name, "could not parse bottle filename #{filename}"
          return
        end

        pkg_version = filename.delete_prefix("portable-ruby--")
                              .sub(/\.#{Regexp.escape(tag_string)}\.bottle.*\.tar\.gz\z/, "")
        if pkg_version.empty?
          failed formula_name, "could not parse portable-ruby version from #{filename}"
          return
        end

        tag_symbol = tag_string.to_sym
        bottle_tag = Utils::Bottles::Tag.from_symbol(tag_symbol)
        sha256 = bottle_file.sha256
        version = pkg_version.split("_").first.to_s

        vendor_dir = HOMEBREW_LIBRARY_PATH/"vendor"
        (vendor_dir/"portable-ruby-version").atomic_write("#{pkg_version}\n")
        (HOMEBREW_LIBRARY_PATH/".ruby-version").atomic_write("#{version}\n")
        os = bottle_tag.linux? ? "linux" : "darwin"
        platform_file = vendor_dir/"portable-ruby-#{bottle_tag.standardized_arch}-#{os}"
        platform_file.atomic_write("ruby_TAG=#{tag_symbol}\nruby_SHA=#{sha256}\n")

        # Seed `HOMEBREW_CACHE` so `brew vendor-install ruby` finds the just-built
        # bottle locally instead of trying to download it.
        HOMEBREW_CACHE.mkpath
        FileUtils.cp(bottle_file, HOMEBREW_CACHE/"portable-ruby-#{pkg_version}.#{tag_symbol}.bottle.tar.gz")

        test "brew", "vendor-install", "ruby"

        bundler_version = Utils::PortableRuby.sync_bundler_version!(pkg_version)
        test "brew", "vendor-gems", "--no-commit", "--update=--ruby,--bundler=#{bundler_version}"
        test "brew", "typecheck", "--update"

        # Run the checks that gate a Homebrew/brew pull request.
        test "brew", "style"
        test "brew", "typecheck"
        test "brew", "install-bundler-gems", "--groups=all"
        test "brew", "vendor-gems", "--non-bundler-gems", "--no-commit"
        test "brew", "tests", "--online", "--coverage"
        test "brew", "tests", "--generic", "--coverage"
        test "brew", "update-test"
        test "brew", "update-test", "--to-tag"
        test "brew", "update-test", "--commit=HEAD"
        test "brew", "test-bot", "--only-formulae", "--only-json-tab", "--test-default-formula",
             env: { "GITHUB_ACTIONS" => nil }
      end

      sig { params(formula_name: String).void }
      def deleted_formula!(formula_name)
        test_header(:Formulae, method: "deleted_formula!(#{formula_name})")

        test "brew", "uses",
             "--formula",
             "--include-build",
             "--include-optional",
             "--include-test",
             formula_name,
             env: require_current_tap_trust_env
      end

      sig { returns(T::Boolean) }
      def testing_portable_ruby?
        !!tap&.core_tap? && @testing_formulae.include?("portable-ruby")
      end
    end
  end
end
