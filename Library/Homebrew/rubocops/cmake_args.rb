# typed: strict
# frozen_string_literal: true

require "rubocops/extend/formula_cop"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop checks for a positional CMake source directory, which implicitly
      # builds in the working directory.
      class CMakeArgs < FormulaCop
        extend AutoCorrector

        MSG = "Use explicit `-S` and `-B` arguments for CMake."

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          return if (body_node = formula_nodes.body_node).nil?

          find_every_method_call_by_name(body_node, :system).each do |method|
            next if method.receiver

            args = parameters(method)
            command, source_dir = args
            next unless node_equals?(command, "cmake")
            # A leading argument that isn't an option is a positional source directory,
            # which implicitly builds in the working directory.
            next unless source_dir.is_a?(RuboCop::AST::StrNode)
            next if source_dir.value.start_with?("-")

            # `-S` and `-B` can be joined to their values, e.g. `-Bbuild`.
            options = args.filter_map { |arg| arg.value if arg.is_a?(RuboCop::AST::StrNode) }
            next if options.any? { |option| option.start_with?("-S") }

            # Only add a build directory when the call doesn't already give one.
            replacement = if options.any? { |option| option.start_with?("-B") }
              %Q("-S", #{source_dir.source})
            else
              %Q("-S", #{source_dir.source}, "-B", ".")
            end

            offending_node(source_dir)
            problem MSG do |corrector|
              corrector.replace(source_dir.source_range, replacement)
            end
          end
        end
      end
    end
  end
end
