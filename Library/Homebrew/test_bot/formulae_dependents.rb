# typed: strict
# frozen_string_literal: true

module Homebrew
  module TestBot
    class FormulaeDependents < TestFormulae
      DependentWithDependencies = T.type_alias { [Formula, T::Array[Dependency]] }
      private_constant :DependentWithDependencies

      sig { params(testing_formulae: T::Array[String]).returns(T::Array[String]) }
      attr_writer :testing_formulae

      sig { params(tested_formulae: T::Array[String]).returns(T::Array[String]) }
      attr_writer :tested_formulae

      sig {
        params(
          tap:       T.nilable(Tap),
          git:       T.nilable(String),
          dry_run:   T::Boolean,
          fail_fast: T::Boolean,
          verbose:   T::Boolean,
        ).void
      }
      def initialize(tap:, git:, dry_run:, fail_fast:, verbose:)
        super
        @testing_formulae_with_tested_dependents = T.let([], T::Array[String])
        @tested_dependents_list = T.let(nil, T.nilable(Pathname))
        @dependent_testing_formulae = T.let([], T::Array[String])
        @tested_dependents = T.let([], T::Array[String])
        @formulae_dependents_filter = T.let(nil, T.nilable(T::Array[String]))
        @dependent_pairs_by_formula = T.let({}, T::Hash[String, T::Array[DependentWithDependencies]])
      end

      sig { params(args: Homebrew::Cmd::TestBotCmd::Args).void }
      def run!(args:)
        if args.formulae_dependents_shard.present? && !args.only_formulae_dependents?
          raise UsageError, "`--formulae-dependents-shard` requires `--only-formulae-dependents`."
        end

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

        download_artifacts_from_previous_run!("dependents{,_#{previous_run_artifact_specifier}*}",
                                              dry_run: args.dry_run?)
        @skip_candidates = T.let(
          if (tested_dependents_cache = artifact_cache/@tested_dependents_list).exist?
            tested_dependents_cache.read.split("\n")
          else
            []
          end,
          T.nilable(T::Array[String]),
        )

        if args.formulae_dependents_shard.present?
          dependent_pairs = @dependent_testing_formulae.flat_map do |formula_name|
            dependent_pairs_for_formula(Formulary.factory(formula_name), formula_name, args:)
          end
          dependent_pairs.uniq! { |dependent, _| dependent.full_name }

          @formulae_dependents_filter = dependents_for_shard(dependent_pairs, args.formulae_dependents_shard.to_s)
                                        .map { |dependent, _| dependent.full_name }
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

      sig { params(installable_bottles: T::Array[String], args: Homebrew::Cmd::TestBotCmd::Args).void }
      def install_formulae_if_needed_from_bottles!(installable_bottles, args:)
        installable_bottles.each do |formula_name|
          formula = Formulary.factory(formula_name)
          next if formula.latest_version_installed?

          install_formula_from_bottle!(formula_name, testing_formulae_dependents: true, dry_run: args.dry_run?)
        end
      end

      sig { params(formula_name: String, args: Homebrew::Cmd::TestBotCmd::Args).void }
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
        return unless steps.fetch(-1).passed?

        # Restore etc/var files that may have been nuked in the build stage.
        test "brew", "postinstall",
             named_args:      formula_name,
             ignore_failures: !bottled?(formula, no_older_versions: true)
        return unless steps.fetch(-1).passed?

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

        @tested_dependents |= (source_dependents + bottled_dependents).map(&:full_name)
      end

      sig {
        params(formula: Formula, formula_name: String, args: Homebrew::Cmd::TestBotCmd::Args)
          .returns([T::Array[Formula], T::Array[Formula], T::Array[Formula]])
      }
      def dependents_for_formula(formula, formula_name, args:)
        info_header "Determining dependents..."

        dependents = dependent_pairs_for_formula(formula, formula_name, args:)
        if (filter = @formulae_dependents_filter)
          dependents = dependents.select do |dependent, _|
            filter.include?(dependent.name) || filter.include?(dependent.full_name)
          end
        end
        dependents.reject! { |dependent, _| @tested_dependents.include?(dependent.full_name) }

        # Split into dependents that we could potentially be building from source and those
        # we should not. The criteria is that a dependent must have bottled dependencies, and
        # either the `--build-dependents-from-source` flag was passed or a dependent has no
        # bottle on the current OS.
        source_dependents, dependents = dependents.partition do |dependent, deps|
          next false unless build_dependent_from_source?(dependent)

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

      sig {
        params(formula: Formula, formula_name: String, args: Homebrew::Cmd::TestBotCmd::Args)
          .returns(T::Array[DependentWithDependencies])
      }
      def dependent_pairs_for_formula(formula, formula_name, args:)
        @dependent_pairs_by_formula[formula_name] ||= begin
          # Always skip recursive dependents on Intel. It's really slow.
          # Also skip recursive dependents on Linux unless it's a Linux-only formula.
          #
          skip_recursive_dependents = skip_recursive_dependents?(formula, args:)

          uses_args = %w[--formula]
          uses_include_test_args = [*uses_args, "--include-test"]
          uses_include_test_args << "--recursive" unless skip_recursive_dependents
          uses_env = require_current_tap_trust_env.merge("HOMEBREW_STDERR" => "1")
          dependents = with_env(uses_env) do
            Utils.safe_popen_read("brew", "uses", *uses_include_test_args, formula_name)
                 .split("\n")
          end

          # TODO: Consider handling the following case better.
          #       `foo` has a build dependency on `bar`, and `bar` has a runtime dependency on
          #       `baz`. When testing `baz` with `--build-dependents-from-source`, `foo` is
          #       not tested, but maybe should be.
          dependents += with_env(uses_env) do
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
              Dependency.expand(f, cache_key: "test-bot-dependents") do |_, dependency|
                next Dependable::SKIP if dependency.implicit?
                next Dependable::KEEP_BUT_PRUNE_RECURSIVE_DEPS if dependency.build? || dependency.test?
              end
            end.reject(&:optional?)
          end)

          # Defer formulae which could be tested later
          # i.e. formulae that also depend on something else yet to be built in this test run.
          unless args.only_formulae_dependents?
            dependents.reject! do |_, deps|
              still_to_test = @dependent_testing_formulae - @testing_formulae_with_tested_dependents
              deps.map { |d| d.to_formula.full_name }.intersect?(still_to_test)
            end
          end

          dependents
        end
      end

      sig {
        params(
          dependents: T::Array[DependentWithDependencies],
          shard:      String,
        ).returns(T::Array[DependentWithDependencies])
      }
      def dependents_for_shard(dependents, shard)
        unless shard.match?(%r{\A[1-9]\d*/[1-9]\d*\z})
          raise UsageError, "`--formulae-dependents-shard` must use the format <SHARD/TOTAL>."
        end

        shard_parts = shard.split("/", 2)
        shard_index = shard_parts.fetch(0).to_i
        shard_count = shard_parts.fetch(1).to_i
        if shard_index > shard_count
          raise UsageError, "`--formulae-dependents-shard` must not be greater than the total shard count."
        end

        return dependents if shard_count == 1

        dependents_by_name = dependents.to_h { |dependent, deps| [dependent.full_name, [dependent, deps]] }
        edges = dependents.to_h { |dependent, _| [dependent.full_name, T.let([], T::Array[String])] }

        dependents.each do |dependent, deps|
          deps.each do |dep|
            dep_name = dep.to_formula.full_name
            next unless edges.key?(dep_name)

            edges.fetch(dependent.full_name) << dep_name
            edges.fetch(dep_name) << dependent.full_name
          end
        end

        seen = T.let(Set.new, T::Set[String])
        groups = T.let([], T::Array[T::Array[DependentWithDependencies]])
        max_group_size = (dependents.size + shard_count - 1) / shard_count

        dependents.map(&:first).each do |dependent|
          next if seen.include?(dependent.full_name)

          group = T.let([], T::Array[DependentWithDependencies])
          queue = T.let([dependent.full_name], T::Array[String])

          until queue.empty?
            name = queue.fetch(0)
            queue.shift
            next if seen.include?(name)

            seen << name
            group << dependents_by_name.fetch(name)
            break if group.size >= max_group_size

            queue.concat(edges.fetch(name).reject { |edge| seen.include?(edge) })
          end

          groups << group
        end

        shards = Array.new(shard_count) { T.let([], T::Array[DependentWithDependencies]) }
        groups.sort_by { |group| [-group.count, group.map { |dependent, _| dependent.full_name }.min.to_s] }
              .each do |group|
          group_shard_index = 0
          shards.each_with_index do |current_shard, index|
            group_shard_index = index if current_shard.count < shards.fetch(group_shard_index).count
          end
          shards.fetch(group_shard_index).concat(group)
        end

        shards.fetch(shard_index - 1).sort_by { |dependent, _| dependent.full_name }
      end

      sig {
        params(
          dependent:           Formula,
          testable_dependents: T::Array[Formula],
          args:                Homebrew::Cmd::TestBotCmd::Args,
          build_from_source:   T::Boolean,
        ).void
      }
      def install_dependent(dependent, testable_dependents, args:, build_from_source: false)
        if @skip_candidates&.include?(dependent.full_name) &&
           artifact_cache_valid?(dependent, formulae_dependents: true)
          @tested_dependents_list&.write(dependent.full_name, mode: "a")
          @tested_dependents_list&.write("\n", mode: "a")
          skipped dependent.name, "#{dependent.full_name} has been tested at #{previous_github_sha}"
          return
        end

        if (messages = unsatisfied_requirements_messages(dependent))
          skipped dependent.name, messages
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

          next Dependable::PRUNE
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
            return if steps.fetch(-1).failed?
          else
            fetch_formulae << dependent.full_name
          end

          if fetch_formulae.present?
            test "brew", "fetch", "--retry", *fetch_formulae
            return if steps.fetch(-1).failed?
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
          install_step = steps.fetch(-1)

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
        linkage_step = steps.fetch(-1)

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
          test_step = steps.fetch(-1)
        end

        test "brew", "uninstall", "--force", "--ignore-dependencies", dependent.full_name

        all_tests_passed = (dependent_was_previously_installed || install_step.passed?) &&
                           linkage_step.passed? &&
                           (testable_dependents.exclude?(dependent) || test_step&.passed?)

        if all_tests_passed
          @tested_dependents_list&.write(dependent.full_name, mode: "a")
          @tested_dependents_list&.write("\n", mode: "a")
        end

        return unless GitHub::Actions.env_set?

        if build_from_source &&
           !bottled_on_current_version &&
           !dependent_was_previously_installed &&
           all_tests_passed &&
           dependent.deps.all? { |d| bottled?(d.to_formula, no_older_versions: true) }
          puts GitHub::Actions::Annotation.new(
            :notice,
            "All tests passed.",
            file:  dependent.path.to_s.delete_prefix("#{repository}/"),
            title: "#{dependent} should be bottled for #{Homebrew::TestBot.runner_os_title}!",
          )
        end
      end

      sig { params(_formula: Formula, args: Homebrew::Cmd::TestBotCmd::Args).returns(T::Boolean) }
      def skip_recursive_dependents?(_formula, args:)
        args.skip_recursive_dependents? != false
      end

      sig { params(_dependent: Formula).returns(T::Boolean) }
      def build_dependent_from_source?(_dependent)
        true
      end

      sig { params(formula: Formula).void }
      def unlink_conflicts(formula)
        return if formula.keg_only?
        return if formula.linked_keg.exist?

        conflicts = formula.conflicts.map { |c| Formulary.factory(c.name) }.select(&:any_version_installed?)
        formula_recursive_dependencies = formula.recursive_dependencies
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
