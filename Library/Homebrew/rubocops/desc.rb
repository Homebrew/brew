# typed: strict
# frozen_string_literal: true

require "rubocops/extend/formula_cop"
require "rubocops/shared/desc_helper"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop audits `desc` in formulae.
      # See the {DescHelper} module for details of the checks.
      class Desc < FormulaCop
        include DescHelper
        extend AutoCorrector

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          body_node = formula_nodes.body_node

          @name = T.let(@formula_name, T.nilable(String))
          desc_call = find_node_method_by_name(body_node, :desc)
          offending_node(formula_nodes.class_node) if body_node.nil?
          audit_desc(:formula, @name, desc_call)
        end
      end
    end
  end
end
