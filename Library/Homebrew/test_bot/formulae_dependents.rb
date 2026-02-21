# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Homebrew
  module TestBot
    class FormulaeDependents < TestFormulae
      attr_writer :testing_formulae, :tested_formulae

      def run!(args:)
        test "brew", "untap", "--force", "homebrew/cask" if !tap&.core_cask_tap? && CoreCaskTap.instance.installed?

        installable_bottles = @tested_formulae - @skipped_or_failed_formulae
        unneeded_formulae = @tested_formulae - @testing_formulae
        @skipped_or_failed_formulae += unneeded_formulae

        info_header "Skipped or failed formulae:"
        puts skipped_or_failed_formulae

        @testing_formulae_with_tested_dependents = []
        @tested_dependents_list = Pathname("tested-dependents-#{Utils::Bottles.tag}.txt")

        @dependent_testing_formulae = sorted_formulae - skipped_or_failed_formulae

        install_formulae_if_needed_from_bottles!(installable_bottles, args:)

        # TODO: move to extend/os
        # rubocop:todo Homebrew/MoveToExtendOS
        artifact_specifier = if OS.linux?
          "{linux,ubuntu}"
        else
          "{macos-#{MacOS.version},#{MacOS.version}-#{Hardware::CPU.arch}}"
        end
        # rubocop:enable Homebrew/MoveToExtendOS

        download_artifacts_from_previous_run!("dependents{,_#{artifact_specifier}*}", dry_run: args.dry_run?)
        @skip_candidates = if (tested_dependents_cache = artifact_cache/@tested_dependents_list).exist?
          tested_dependents_cache.read.split("\n")
        else
          []
        end

        @dependent_testing_formulae.each do |formula_name|
          dependent_formulae!(formula_name, args:)
          puts
        end

        return unless GitHub::Actions.env_set?

        # Remove `bash` after it is tested, since leaving a broken `bash`
        # installation in the environment can cause issues with subsequent
        # GitHub Actions steps.
        return unless @dependent_testing_formulae.include?("bash")

        test "brew", "uninstall", "--formula", "--force", "bash"
      end

      private

      def install_formulae_if_needed_from_bottles!(installable_bottles, args:)
        installable_bottles.each do |formula_name|
          formula = Formulary.factory(formula_name)
          next if formula.latest_version_installed?

          install_formula_from_bottle!(formula_name, testing_formulae_dependents: true, dry_run: args.dry_run?)
        end
      end

      def dependent_formulae!(formula_name, args:)
        cleanup_during!(@dependent_testing_formulae, args:)

        test_header(:FormulaeDependents, method: "dependent_formulae!(#{formula_name})")
        @testing_formulae_with_tested_dependents << formula_name

        formula = Formulary.factory(formula_name)

        source_dependents, bottled_dependents, testable_dependents =
          dependents_for_formula(formula, formula_name, args:)

        return if source_dependents.blank? && bottled_dependents.blank? && testable_dependents.blank?

        # If we installed this from a bottle, then the formula isn't linked.
        # If the formula isn't linked, `brew install --only-dependences` does
        # nothing with the message:
        #     Warning: formula x.y.z is already installed, it's just not linked.
        #     To link this version, run:
        #       brew link formula
        unlink_conflicts formula
        test "brew", "link", formula_name unless formula.keg_only?

        # Install formula dependencies. These may not be installed.
        test "brew", "install", "--only-dependencies",
             named_args:      formula_name,
             ignore_failures: !bottled?(formula, no_older_versions: true),
             env:             { "HOMEBREW_DEVELOPER" => nil }
        return unless steps.last.passed?

        # Restore etc/var files that may have been nuked in the build stage.
        test "brew", "postinstall",
             named_args:      formula_name,
             ignore_failures: !bottled?(formula, no_older_versions: true)
        return unless steps.last.passed?

        # Test texlive first to avoid GitHub-hosted runners running out of storage.
        # TODO: Try generalising this by sorting dependents according to install size,
        #       where ideally install size should include recursive dependencies.
        [source_dependents, bottled_dependents].each do |dependent_array|
          texlive = dependent_array.find { |dependent| dependent.name == "texlive" }
          next unless texlive.present?

          dependent_array.delete(texlive)
          dependent_array.unshift(texlive)
        end

        source_dependents.each do |dependent|
          install_dependent(dependent, testable_dependents, build_from_source: true, args:)
          install_dependent(dependent, testable_dependents, args:) if bottled?(dependent)
        end

        bottled_dependents.each do |dependent|
          install_dependent(dependent, testable_dependents, args:)
        end
      end

      def dependents_for_formula(formula, formula_name, args:)
        info_header "Determining dependents..."

        # Always skip recursive dependents on Intel. It's really slow.
        # Also skip recursive dependents on Linux unless it's a Linux-only formula.
        #
        # TODO: move to extend/os
        # rubocop:todo Homebrew/MoveToExtendOS
        skip_recursive_dependents = args.skip_recursive_dependents? ||
                                    (OS.mac? && Hardware::CPU.intel?) ||
                                    (OS.linux? && formula.requirements.exclude?(LinuxRequirement.new))
        # rubocop:enable Homebrew/MoveToExtendOS

        uses_args = %w[--formula --eval-all]
        uses_include_test_args = [*uses_args, "--include-test"]
        uses_include_test_args << "--recursive" unless skip_recursive_dependents
        dependents = with_env(HOMEBREW_STDERR: "1") do
          Utils.safe_popen_read("brew", "uses", *uses_include_test_args, formula_name)
               .split("\n")
        end

        # TODO: Consider handling the following case better.
        #       `foo` has a build dependency on `bar`, and `bar` has a runtime dependency on
        #       `baz`. When testing `baz` with `--build-dependents-from-source`, `foo` is
        #       not tested, but maybe should be.
        dependents += with_env(HOMEBREW_STDERR: "1") do
          Utils.safe_popen_read("brew", "uses", *uses_args, "--include-build", formula_name)
               .split("\n")
        end
        dependents.uniq!
        dependents.sort!

        dependents -= @tested_formulae
        dependents = dependents.map { |d| Formulary.factory(d) }

        dependents = dependents.zip(dependents.map do |f|
          if skip_recursive_dependents
            f.deps.reject(&:implicit?)
          else
            begin
              Dependency.expand(f, cache_key: "test-bot-dependents") do |_, dependency|
                Dependency.skip if dependency.implicit?
                Dependency.keep_but_prune_recursive_deps if dependency.build? || dependency.test?
              end
            rescue TapFormulaUnavailableError => e
              raise if e.tap.installed?

              e.tap.clear_cache
              safe_system "brew", "tap", e.tap.name
              retry
            end
          end.reject(&:optional?)
        end)

        # Defer formulae which could be tested later
        # i.e. formulae that also depend on something else yet to be built in this test run.
        dependents.reject! do |_, deps|
          still_to_test = @dependent_testing_formulae - @testing_formulae_with_tested_dependents
          deps.map { |d| d.to_formula.full_name }.intersect?(still_to_test)
        end

        # Split into dependents that we could potentially be building from source and those
        # we should not. The criteria is that a dependent must have bottled dependencies, and
        # either the `--build-dependents-from-source` flag was passed or a dependent has no
        # bottle on the current OS.
        source_dependents, dependents = dependents.partition do |dependent, deps|
          # TODO: move to extend/os
          # rubocop:todo Homebrew/MoveToExtendOS
          next false if OS.linux? && dependent.requirements.exclude?(LinuxRequirement.new)
          # rubocop:enable Homebrew/MoveToExtendOS

          all_deps_bottled_or_built = deps.all? do |d|
            bottled_or_built?(d.to_formula, @dependent_testing_formulae)
          end
          args.build_dependents_from_source? && all_deps_bottled_or_built
        end

        # From the non-source list, get rid of any dependents we are only a build dependency to
        dependents.select! do |_, deps|
          deps.reject { |d| d.build? && !d.test? }
              .map(&:to_formula)
              .include?(formula)
        end

        dependents = dependents.transpose.first.to_a
        source_dependents = source_dependents.transpose.first.to_a

        testable_dependents = source_dependents.select(&:test_defined?)
        bottled_dependents = dependents.select { |dep| bottled?(dep) }
        testable_dependents += bottled_dependents.select(&:test_defined?)

        info_header "Source dependents:"
        puts source_dependents

        info_header "Bottled dependents:"
        puts bottled_dependents

        info_header "Testable dependents:"
        puts testable_dependents

        [source_dependents, bottled_dependents, testable_dependents]
      end

      def install_dependent(dependent, testable_dependents, args:, build_from_source: false)
        if @skip_candidates.include?(dependent.full_name) &&
           artifact_cache_valid?(dependent, formulae_dependents: true)
          @tested_dependents_list.write(dependent.full_name, mode: "a")
          @tested_dependents_list.write("\n", mode: "a")
          skipped dependent.name, "#{dependent.full_name} has been tested at #{previous_github_sha}"
          return
        end

        if (messages = unsatisfied_requirements_messages(dependent))
          skipped dependent, messages
          return
        end

        if dependent.deprecated? || dependent.disabled?
          verb = dependent.deprecated? ? :deprecated : :disabled
          skipped dependent.name, "#{dependent.full_name} has been #{verb}!"
          return
        end

        cleanup_during!(@dependent_testing_formulae, args:)

        required_dependent_deps = dependent.deps.reject(&:optional?)
        bottled_on_current_version = bottled?(dependent, no_older_versions: true)
        dependent_was_previously_installed = dependent.latest_version_installed?

        dependent_dependencies = Dependency.expand(
          dependent,
          cache_key: "test-bot-dependent-dependencies-#{dependent.full_name}",
        ) do |dep_dependent, dependency|
          next if !dependency.build? && !dependency.test? && !dependency.optional?
          next if dependency.test? &&
                  dep_dependent == dependent &&
                  !dependency.optional? &&
                  testable_dependents.include?(dependent)

          Dependency.prune
        end

        unless dependent_was_previously_installed
          build_args = []

          fetch_formulae = dependent_dependencies.reject(&:satisfied?).map(&:name)

          if build_from_source
            required_dependent_reqs = dependent.requirements.reject(&:optional?)
            install_curl_if_needed(dependent)
            install_mercurial_if_needed(required_dependent_deps, required_dependent_reqs)
            install_subversion_if_needed(required_dependent_deps, required_dependent_reqs)

            build_args << "--build-from-source"

            test "brew", "fetch", "--build-from-source", "--retry", dependent.full_name
            return if steps.last.failed?
          else
            fetch_formulae << dependent.full_name
          end

          if fetch_formulae.present?
            test "brew", "fetch", "--retry", *fetch_formulae
            return if steps.last.failed?
          end

          unlink_conflicts dependent

          test "brew", "install", *build_args, "--only-dependencies",
               named_args:      dependent.full_name,
               ignore_failures: !bottled_on_current_version,
               env:             { "HOMEBREW_DEVELOPER" => nil }

          env = {}
          env["HOMEBREW_GIT_PATH"] = nil if build_from_source && required_dependent_deps.any? do |d|
            d.name == "git" && (!d.test? || d.build?)
          end
          test "brew", "install", *build_args,
               named_args:      dependent.full_name,
               env:             env.merge({ "HOMEBREW_DEVELOPER" => nil }),
               ignore_failures: !args.test_default_formula? && !bottled_on_current_version
          install_step = steps.last

          return unless install_step.passed?
        end
        return unless dependent.latest_version_installed?

        if !dependent.keg_only? && !dependent.linked_keg.exist?
          unlink_conflicts dependent
          test "brew", "link", dependent.full_name
        end
        test "brew", "install", "--only-dependencies", dependent.full_name
        test "brew", "linkage", "--test",
             named_args:      dependent.full_name,
             ignore_failures: !args.test_default_formula? && !bottled_on_current_version
        linkage_step = steps.last

        if linkage_step.passed? && !build_from_source
          # Check for opportunistic linkage. Ignore failures because
          # they can be unavoidable but we still want to know about them.
          test "brew", "linkage", "--cached", "--test", "--strict",
               named_args:      dependent.full_name,
               ignore_failures: !args.test_default_formula?
        end

        if testable_dependents.include? dependent
          test "brew", "install", "--only-dependencies", "--include-test", dependent.full_name

          dependent_dependencies.each do |dependency|
            dependency_f = dependency.to_formula
            next if dependency_f.keg_only?
            next if dependency_f.linked?

            unlink_conflicts dependency_f
            test "brew", "link", dependency_f.full_name
          end

          env = {}
          env["HOMEBREW_GIT_PATH"] = nil if required_dependent_deps.any? do |d|
            d.name == "git" && (!d.build? || d.test?)
          end
          test "brew", "test", "--retry", "--verbose",
               named_args:      dependent.full_name,
               env:,
               ignore_failures: !args.test_default_formula? && !bottled_on_current_version
          test_step = steps.last
        end

        test "brew", "uninstall", "--force", "--ignore-dependencies", dependent.full_name

        all_tests_passed = (dependent_was_previously_installed || install_step.passed?) &&
                           linkage_step.passed? &&
                           (testable_dependents.exclude?(dependent) || test_step.passed?)

        if all_tests_passed
          @tested_dependents_list.write(dependent.full_name, mode: "a")
          @tested_dependents_list.write("\n", mode: "a")
        end

        return unless GitHub::Actions.env_set?

        if build_from_source &&
           !bottled_on_current_version &&
           !dependent_was_previously_installed &&
           all_tests_passed &&
           dependent.deps.all? { |d| bottled?(d.to_formula, no_older_versions: true) }
          # TODO: move to extend/os
          # rubocop:todo Homebrew/MoveToExtendOS
          os_string = if OS.mac?
            str = "macOS #{MacOS.version.pretty_name} (#{MacOS.version})"
            str << " on Apple Silicon" if Hardware::CPU.arm?

            str
          else
            OS.kernel_name
          end
          # rubocop:enable Homebrew/MoveToExtendOS

          puts GitHub::Actions::Annotation.new(
            :notice,
            "All tests passed.",
            file:  dependent.path.to_s.delete_prefix("#{repository}/"),
            title: "#{dependent} should be bottled for #{os_string}!",
          )
        end
      end

      def unlink_conflicts(formula)
        return if formula.keg_only?
        return if formula.linked_keg.exist?

        conflicts = formula.conflicts.map { |c| Formulary.factory(c.name) }.select(&:any_version_installed?)
        formula_recursive_dependencies = begin
          formula.recursive_dependencies
        rescue TapFormulaUnavailableError => e
          raise if e.tap.installed?

          e.tap.clear_cache
          safe_system "brew", "tap", e.tap.name
          retry
        end
        formula_recursive_dependencies.each do |dependency|
          conflicts += dependency.to_formula.conflicts.map do |c|
            Formulary.factory(c.name)
          end.select(&:any_version_installed?)
        end
        conflicts.each do |conflict|
          test "brew", "unlink", conflict.name
        end
      end
    end
  end
end
