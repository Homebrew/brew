# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "abstract_command"
require "formula"
require "cask/caskroom"
require "dependencies_helpers"

module Homebrew
  module Cmd
    class Deps < AbstractCommand
      include DependenciesHelpers
      cmd_args do
        description <<~EOS
          Show dependencies for <formula>. When given multiple formula arguments,
          show the intersection of dependencies for each formula. By default, `deps`
          shows all required and recommended dependencies.

          If any version of each formula argument is installed and no other options
          are passed, this command displays their actual runtime dependencies (similar
          to `brew linkage`), which may differ from the current versions' stated
          dependencies if the installed versions are outdated.

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
               description: "Include implicit dependencies used to download and unpack source files"
        switch "--include-build",
               description: "Include `:build` dependencies for <formula>."
        switch "--include-optional",
               description: "Include `:optional` dependencies for <formula>."
        switch "--include-test",
               description: "Include `:test` dependencies for <formula> (non-recursive)."
        switch "--skip-recommended",
               description: "Skip `:recommended` dependencies for <formula>."
        switch "--include-requirements",
               description: "Include requirements in addition to dependencies for <formula>."
        switch "--tree",
               description: "Show dependencies as a tree. When given multiple formula arguments, " \
                            "show individual trees for each formula."
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
        switch "--missing",
               description: "Show only missing dependencies."
        switch "--eval-all",
               description: "Evaluate all available formulae and casks, whether installed or not, to list " \
                            "their dependencies."
        switch "--for-each",
               description: "Switch into the mode used by the `--eval-all` option, but only list dependencies " \
                            "for each provided <formula>, one formula per line. This is used for " \
                            "debugging the `--installed`/`--eval-all` display mode."
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
        conflicts "--formula", "--cask"
        formula_options

        named_args [:formula, :cask]
      end

      sig { override.void }
      def run
        raise UsageError, "`brew deps --os=all` is not supported" if args.os == "all"
        raise UsageError, "`brew deps --arch=all` is not supported" if args.arch == "all"

        os, arch = T.must(args.os_arch_combinations.first)
        all = args.eval_all?

        Formulary.enable_factory_cache!

        SimulateSystem.with(os:, arch:) do
          recursive = !args.direct?
          installed = args.installed? || dependents(args.named.to_formulae_and_casks).all?(&:any_version_installed?)

          @use_runtime_dependencies = installed && recursive &&
                                      !args.tree? &&
                                      !args.graph? &&
                                      !args.HEAD? &&
                                      !args.include_implicit? &&
                                      !args.include_build? &&
                                      !args.include_test? &&
                                      !args.include_optional? &&
                                      !args.skip_recommended? &&
                                      !args.missing? &&
                                      args.os.nil? &&
                                      args.arch.nil?

          if args.tree? || args.graph?
            dependents = if args.named.present?
              sorted_dependents(args.named.to_formulae_and_casks)
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
          elsif all
            puts_deps(sorted_dependents(
                        Formula.all(eval_all: args.eval_all?) + Cask::Cask.all(eval_all: args.eval_all?),
                      ), recursive:)
            return
          elsif !args.no_named? && args.for_each?
            puts_deps(sorted_dependents(args.named.to_formulae_and_casks), recursive:)
            return
          end

          if args.no_named?
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

          dependents = dependents(args.named.to_formulae_and_casks)
          check_head_spec(dependents) if args.HEAD?

          all_deps = deps_for_dependents(dependents, recursive:, &(args.union? ? :| : :&))
          condense_requirements(all_deps)
          all_deps.map! { |d| dep_display_name(d) }
          all_deps.uniq!
          all_deps.sort! unless args.topological?
          puts all_deps
        end
      end

      private

      def sorted_dependents(formulae_or_casks)
        dependents(formulae_or_casks).sort_by(&:name)
      end

      def condense_requirements(deps)
        deps.select! { |dep| dep.is_a?(Dependency) } unless args.include_requirements?
        deps.select! { |dep| dep.is_a?(Requirement) || dep.installed? } if args.installed?
      end

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

      def deps_for_dependent(dependency, recursive: false)
        includes, ignores = args_includes_ignores(args)

        deps = dependency.runtime_dependencies if @use_runtime_dependencies

        if recursive
          deps ||= recursive_includes(Dependency, dependency, includes, ignores)
          reqs   = recursive_includes(Requirement, dependency, includes, ignores)
        else
          deps ||= select_includes(dependency.deps, ignores, includes)
          reqs   = select_includes(dependency.requirements, ignores, includes)
        end

        deps + reqs.to_a
      end

      def deps_for_dependents(dependents, recursive: false, &block)
        dependents.map { |d| deps_for_dependent(d, recursive:) }.reduce(&block)
      end

      def check_head_spec(dependents)
        headless = dependents.select { |d| d.is_a?(Formula) && d.active_spec_sym != :head }
                             .to_sentence two_words_connector: " or ", last_word_connector: " or "
        opoo "No head spec for #{headless}, using stable spec instead" unless headless.empty?
      end

      def puts_deps(dependents, recursive: false)
        check_head_spec(dependents) if args.HEAD?
        dependents.each do |dependent|
          deps = deps_for_dependent(dependent, recursive:)
          condense_requirements(deps)
          deps.sort_by!(&:name)
          deps.map! { |d| dep_display_name(d) }
          puts "#{dependent.full_name}: #{deps.join(" ")}"
        end
      end

      def dot_code(dependents, recursive:)
        dep_graph = {}
        dependents.each do |d|
          graph_deps(d, dep_graph:, recursive:)
        end

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

      def puts_deps_tree(dependents, recursive: false)
        check_head_spec(dependents) if args.HEAD?
        dependents.each do |d|
          puts d.full_name
          recursive_deps_tree(d, dep_stack: [], prefix: "", recursive:)
          puts
        end
      end

      def dependables(formula)
        includes, ignores = args_includes_ignores(args)
        deps = @use_runtime_dependencies ? formula.runtime_dependencies : formula.deps
        deps = select_includes(deps, ignores, includes)
        reqs = select_includes(formula.requirements, ignores, includes) if args.include_requirements?
        reqs ||= []
        reqs + deps
      end

      def recursive_deps_tree(formula, dep_stack:, prefix:, recursive:)
        dependables = dependables(formula)
        max = dependables.length - 1
        dep_stack.push formula.name
        dependables.each_with_index do |dep, i|
          tree_lines = if i == max
            "└──"
          else
            "├──"
          end

          display_s = "#{tree_lines} #{dep_display_name(dep)}"

          # Detect circular dependencies and consider them a failure if present.
          is_circular = dep_stack.include?(dep.name)
          if is_circular
            display_s = "#{display_s} (CIRCULAR DEPENDENCY)"
            Homebrew.failed = true
          end

          puts "#{prefix}#{display_s}"

          next if !recursive || is_circular

          prefix_addition = if i == max
            "    "
          else
            "│   "
          end

          next unless dep.is_a? Dependency

          recursive_deps_tree(Formulary.factory(dep.name),
                              dep_stack:,
                              prefix:    prefix + prefix_addition,
                              recursive: true)
        end

        dep_stack.pop
      end
    end
  end
end
