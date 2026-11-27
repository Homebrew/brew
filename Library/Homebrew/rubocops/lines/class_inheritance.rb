# typed: strict
# frozen_string_literal: true

require "rubocops/extend/formula_cop"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop makes sure that a space is used for class inheritance.
      class ClassInheritance < FormulaCop
        extend AutoCorrector

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          parent_class_node = formula_nodes.parent_class_node
          begin_pos = start_column(parent_class_node)
          end_pos = end_column(formula_nodes.class_node)
          return if begin_pos-end_pos == 3

          problem "Use a space in class inheritance: " \
                  "class #{formula_name.capitalize} < #{class_name(parent_class_node)}" do |corrector|
            corrector.replace(range_between(end_pos, begin_pos), " < ")
          end
        end
      end
    end
  end
end
