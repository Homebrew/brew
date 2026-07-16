# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"
require "cask/caskroom"
require "dependencies_helpers"

module Homebrew
  module Cmd
    class Deps < AbstractCommand
      include DependenciesHelpers

      class DepsCombineMode < T::Enum
        enums do
          # enum values are not mutable, and calling .freeze on them breaks Sorbet
          # rubocop:disable Style/MutableConstant
          Intersection = new
          Union = new
          # rubocop:enable Style/MutableConstant
        end
      end

      cmd_args do
        description <<~EOS
          Show dependencies for <formula>. When given multiple formula arguments,
          show the intersection of dependencies for each formula. By default, `deps`
          shows all required and recommended dependencies.

          If any version of each formula argument is installed and no other options
          are passed, this command displays their actual runtime dependencies (similar
          to `brew linkage`), which may differ from a formula's declared dependencies.

          *Note:* `--missing` and `--skip-recommended` have precedence over `--include-*`.
        EOS
        switch "-n", "--topological",
               description: "Sort dependencies in topological order."
        switch "-1", "--direct", "--declared", "--1",
               description: "Show only the direct dependencies declared in the formula."
        switch "--union",
               description: "Show the union of dependencies for multiple <formula>, instead of the intersection."
        switch "--full-name",
               description: "List dependencies by their full name."
        switch "--include-implicit",
               description: "Include implicit dependencies used to download and unpack source files."
        switch "--include-build",
               description: "Include `:build` dependencies for <formula>."
        switch "--include-optional",
               description: "Include `:optional` dependencies for <formula>."
        switch "--include-test",
               description: "Include `:test` dependencies for <formula> (non-recursive unless `--graph` or `--tree`)."
        switch "--skip-recommended",
               description: "Skip `:recommended` dependencies for <formula>."
        switch "--include-requirements",
               description: "Include requirements in addition to dependencies for <formula>."
        switch "--tree",
               description: "Show dependencies as a tree. When given multiple formula arguments, " \
                            "show individual trees for each formula."
        switch "--prune",
               depends_on:  "--tree",
               description: "Prune parts of tree already seen."
        switch "--graph",
               description: "Show dependencies as a directed graph."
        switch "--dot",
               depends_on:  "--graph",
               description: "Show text-based graph description in DOT format."
        switch "--annotate",
               description: "Mark any build, test, implicit, optional, or recommended dependencies as " \
                            "such in the output."
        switch "--installed",
               description: "List dependencies for formulae that are currently installed. If <formula> is " \
                            "specified, list only its dependencies that are currently installed."
        flag   "--brewfile",
               description: "Use formulae and casks listed in a Brewfile as inputs. " \
                            "Defaults to `./Brewfile`; use `--brewfile=`<path> to specify another."
        switch "--missing",
               description: "Show only missing dependencies."
        switch "--eval-all",
               description: "Evaluate all available formulae and casks, whether installed or not, to list " \
                            "their dependencies.",
               env:         :eval_all,
               odeprecated: true
        switch "--for-each",
               description: "Switch into the mode used when evaluating all formulae and casks, but only list " \
                            "dependencies for each provided <formula>, one formula per line."
        switch "--HEAD",
               description: "Show dependencies for HEAD version instead of stable version."
        flag   "--os=",
               description: "Show dependencies for the given operating system."
        flag   "--arch=",
               description: "Show dependencies for the given CPU architecture."
        switch "--formula", "--formulae",
               description: "Treat all named arguments as formulae."
        switch "--cask", "--casks",
               description: "Treat all named arguments as casks."

        conflicts "--tree", "--graph"
        conflicts "--installed", "--missing"
        conflicts "--installed", "--eval-all"
        conflicts "--brewfile", "--eval-all"
        conflicts "--formula", "--cask"
        formula_options

        named_args [:formula, :cask]
      end

      sig { override.params(argv: T::Array[String]).void }
      def initialize(argv = ARGV.freeze)
        super
        @use_runtime_dependencies = T.let(true, T::Boolean)
      end

      sig { override.void }
      def run
        raise UsageError, "`brew deps --os=all` is not supported." if args.os == "all"
        raise UsageError, "`brew deps --arch=all` is not supported." if args.arch == "all"

        os, arch = args.os_arch_combinations.fetch(0)
        eval_all = args.eval_all?
        eval_all ||= args.no_named? && !args.installed? && !args.brewfile &&
                     Homebrew::EnvConfig.tap_trust_configured?

        Formulary.enable_factory_cache!

        SimulateSystem.with(os:, arch:) do
          inputs = input_formulae_and_casks
          installed = args.installed? || dependents(inputs).all?(&:any_version_installed?)
          unless installed
            not_using_runtime_dependencies_reason = if args.installed?
              "not all the named formulae were installed"
            else
              "`--installed` was not passed"
            end

            @use_runtime_dependencies = false
          end

          %w[direct tree graph HEAD skip_recommended missing
             include_implicit include_build include_test include_optional].each do |arg|
            next unless args.public_send("#{arg}?")

            not_using_runtime_dependencies_reason = "--#{arg.tr("_", "-")} was passed"

            @use_runtime_dependencies = false
          end

          %w[os arch].each do |arg|
            next if args.public_send(arg).nil?

            not_using_runtime_dependencies_reason = "--#{arg.tr("_", "-")} was passed"

            @use_runtime_dependencies = false
          end

          if !@use_runtime_dependencies && !Homebrew::EnvConfig.no_env_hints?
            opoo <<~EOS
              `brew deps` is not the actual runtime dependencies because #{not_using_runtime_dependencies_reason}!
              This means dependencies may differ from a formula's declared dependencies.
              Hide these hints with `HOMEBREW_NO_ENV_HINTS=1` (see `man brew`).
            EOS
          end

          recursive = !args.direct?

          if args.tree? || args.graph?
            dependents = if inputs.any?
              sorted_dependents(inputs)
            elsif args.installed?
              case args.only_formula_or_cask
              when :formula
                sorted_dependents(Formula.installed)
              when :cask
                sorted_dependents(Cask::Caskroom.casks)
              else
                sorted_dependents(Formula.installed + Cask::Caskroom.casks)
              end
            else
              raise FormulaUnspecifiedError
            end

            if args.graph?
              dot_code = dot_code(dependents, recursive:)
              if args.dot?
                puts dot_code
              else
                exec_browser "https://dreampuf.github.io/GraphvizOnline/##{ERB::Util.url_encode(dot_code)}"
              end
              return
            end

            puts_deps_tree(dependents, recursive:)
            return
          elsif eval_all
            puts_deps(sorted_dependents(
                        Formula.all(eval_all:) + Cask::Cask.all(eval_all:),
                      ), recursive:)
            return
          elsif inputs.any? && args.for_each?
            puts_deps(sorted_dependents(inputs), recursive:)
            return
          end

          if inputs.empty?
            raise FormulaUnspecifiedError unless args.installed?

            sorted_dependents_formulae_and_casks = case args.only_formula_or_cask
            when :formula
              sorted_dependents(Formula.installed)
            when :cask
              sorted_dependents(Cask::Caskroom.casks)
            else
              sorted_dependents(Formula.installed + Cask::Caskroom.casks)
            end
            puts_deps(sorted_dependents_formulae_and_casks, recursive:)
            return
          end

          dependents = dependents(inputs)
          check_head_spec(dependents) if args.HEAD?

          deps_combine_mode = args.union? ? DepsCombineMode::Union : DepsCombineMode::Intersection
          all_deps = deps_for_dependents(dependents, deps_combine_mode:, recursive:)
          condense_requirements(all_deps)
          all_deps.map! { dep_display_name(it) }
          all_deps.uniq!
          all_deps.sort! unless args.topological?
          puts all_deps
        end
      end

      private

      sig { returns(T::Array[T.any(Formula, Keg, Cask::Cask)]) }
      def input_formulae_and_casks
        named = args.named.to_formulae_and_casks
        brewfile = args.brewfile
        return named unless brewfile

        require "bundle/brewfile"
        require "cask/cask_loader"
        only = args.only_formula_or_cask
        from_brewfile = Homebrew::Bundle::Brewfile.read(file: brewfile_path(brewfile)).entries.filter_map do |e|
          case e.type
          when :brew then Formulary.resolve(e.name) if only != :cask
          when :cask then Cask::CaskLoader.load(e.name) if only != :formula
          end
        end
        (named + from_brewfile).uniq
      end

      # A bare `--brewfile` (no `=path`) yields `true` from OptionParser at
      # runtime; the generated RBI types it as `T.nilable(String)`, so accept
      # the wider type here and normalise `true`/`""` to the `nil` default.
      sig { params(value: T.nilable(T.any(String, TrueClass))).returns(T.nilable(String)) }
      def brewfile_path(value)
        value.presence if value.is_a?(String)
      end

      sig {
        params(formulae_or_casks: T::Array[T.any(Formula, Keg, Cask::Cask)])
          .returns(T::Array[T.any(Formula, CaskDependent)])
      }
      def sorted_dependents(formulae_or_casks)
        dependents(formulae_or_casks).sort_by(&:name)
      end

      sig { params(deps: T::Array[T.any(Dependency, Requirement)]).void }
      def condense_requirements(deps)
        deps.select! { |dep| dep.is_a?(Dependency) } unless args.include_requirements?
        deps.select! { |dep| dep.is_a?(Requirement) || dep.installed? } if args.installed?
      end

      sig { params(dep: T.any(Requirement, Dependency)).returns(String) }
      def dep_display_name(dep)
        str = if dep.is_a? Requirement
          if args.include_requirements?
            ":#{dep.display_s}"
          else
            # This shouldn't happen, but we'll put something here to help debugging
            "::#{dep.name}"
          end
        elsif args.full_name?
          dep.to_formula.full_name
        else
          dep.name
        end

        if args.annotate?
          str = "#{str} " if args.tree?
          str = "#{str} [build]" if dep.build?
          str = "#{str} [test]" if dep.test?
          str = "#{str} [optional]" if dep.optional?
          str = "#{str} [recommended]" if dep.recommended?
          str = "#{str} [implicit]" if dep.implicit?
        end

        str
      end

      sig {
        params(dependency: T.any(Formula, CaskDependent), recursive: T::Boolean)
          .returns(T::Array[T.any(Dependency, Requirement)])
      }
      def deps_for_dependent(dependency, recursive: false)
        includes, ignores = args_includes_ignores(args)

        deps = dependency.runtime_dependencies if @use_runtime_dependencies

        if recursive
          deps ||= recursive_dep_includes(dependency, includes, ignores)
          reqs = args.include_requirements? ? recursive_req_includes(dependency, includes, ignores) : Requirements.new
        else
          deps ||= select_includes(dependency.deps, ignores, includes)
          reqs   = select_includes(dependency.requirements, ignores, includes)
        end

        deps + reqs.to_a
      end

      sig {
        params(
          dependents:        T::Array[T.any(Formula, CaskDependent)],
          deps_combine_mode: DepsCombineMode,
          recursive:         T::Boolean,
        ).returns(T::Array[T.any(Dependency, Requirement)])
      }
      def deps_for_dependents(dependents, deps_combine_mode:, recursive:)
        symbol = (deps_combine_mode == DepsCombineMode::Intersection) ? :& : :|
        dependents.map { deps_for_dependent(it, recursive:) }.reduce(symbol)
      end

      sig { params(dependents: T::Array[T.any(Formula, CaskDependent)]).void }
      def check_head_spec(dependents)
        headless = dependents.select { it.is_a?(Formula) && it.active_spec_sym != :head }
                             .to_sentence two_words_connector: " or ", last_word_connector: " or "
        opoo "No head spec for #{headless}, using stable spec instead" unless headless.empty?
      end

      sig { params(dependents: T::Array[T.any(Formula, CaskDependent)], recursive: T::Boolean).void }
      def puts_deps(dependents, recursive: false)
        check_head_spec(dependents) if args.HEAD?
        dependents.each do |dependent|
          deps = deps_for_dependent(dependent, recursive:)
          condense_requirements(deps)
          deps.sort_by!(&:name)
          deps.map! { dep_display_name(it) }
          puts "#{dependent.full_name}: #{deps.join(" ")}"
        end
      end

      sig { params(dependents: T::Array[T.any(Formula, CaskDependent)], recursive: T::Boolean).returns(String) }
      def dot_code(dependents, recursive:)
        dep_graph = {}
        dependents.each { graph_deps(it, dep_graph:, recursive:) }

        dot_code = dep_graph.map do |d, deps|
          deps.map do |dep|
            attributes = []
            attributes << "style = dotted" if dep.build?
            attributes << "arrowhead = empty" if dep.test?
            if dep.optional?
              attributes << "color = red"
            elsif dep.recommended?
              attributes << "color = green"
            end
            comment = " # #{dep.tags.map(&:inspect).join(", ")}" if dep.tags.any?
            "  \"#{d.name}\" -> \"#{dep}\"#{" [#{attributes.join(", ")}]" if attributes.any?}#{comment}"
          end
        end.flatten.join("\n")
        "digraph {\n#{dot_code}\n}"
      end

      sig {
        params(
          formula:   T.any(Formula, CaskDependent),
          dep_graph: T::Hash[T.any(Formula, CaskDependent), T::Array[T.any(Dependency, Requirement)]],
          recursive: T::Boolean,
        ).void
      }
      def graph_deps(formula, dep_graph:, recursive:)
        return if dep_graph.key?(formula)

        dependables = dependables(formula)
        dep_graph[formula] = dependables
        return unless recursive

        dependables.each do |dep|
          next unless dep.is_a? Dependency

          graph_deps(Formulary.factory(dep.name),
                     dep_graph:,
                     recursive: true)
        end
      end

      sig { params(dependents: T::Array[T.any(Formula, CaskDependent)], recursive: T::Boolean).void }
      def puts_deps_tree(dependents, recursive: false)
        check_head_spec(dependents) if args.HEAD?
        dependents.each do |d|
          puts d.full_name
          recursive_deps_tree(d, deps_seen: {}, prefix: "", recursive:)
          puts
        end
      end

      sig { params(formula: T.any(Formula, CaskDependent)).returns(T::Array[T.any(Dependency, Requirement)]) }
      def dependables(formula)
        includes, ignores = args_includes_ignores(args)
        deps = @use_runtime_dependencies ? formula.runtime_dependencies : formula.deps
        deps = select_includes(deps, ignores, includes)
        reqs = select_includes(formula.requirements, ignores, includes) if args.include_requirements?
        reqs ||= []
        reqs + deps
      end

      sig {
        params(
          formula: T.any(Formula, CaskDependent),
          deps_seen: T::Hash[String, T::Boolean],
          prefix: String, recursive: T::Boolean
        ).void
      }
      def recursive_deps_tree(formula, deps_seen:, prefix:, recursive:)
        dependables = dependables(formula)
        max = dependables.length - 1
        deps_seen[formula.name] = true
        dependables.each_with_index do |dep, i|
          tree_lines = if i == max
            "└──"
          else
            "├──"
          end

          display_s = "#{tree_lines} #{dep_display_name(dep)}"

          # Detect circular dependencies and consider them a failure if present.
          is_circular = deps_seen.fetch(dep.name, false)
          pruned = args.prune? && deps_seen.include?(dep.name)
          if is_circular
            display_s = "#{display_s} (CIRCULAR DEPENDENCY)"
            Homebrew.failed = true
          elsif pruned
            display_s = "#{display_s} (PRUNED)"
          end

          puts "#{prefix}#{display_s}"

          next if !recursive || is_circular || pruned

          prefix_addition = if i == max
            "    "
          else
            "│   "
          end

          next unless dep.is_a? Dependency

          recursive_deps_tree(Formulary.factory(dep.name),
                              deps_seen:,
                              prefix:    prefix + prefix_addition,
                              recursive: true)
        end

        deps_seen[formula.name] = false
      end
    end
  end
end
