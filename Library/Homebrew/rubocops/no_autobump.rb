# typed: strict
# frozen_string_literal: true

require "rubocops/extend/formula_cop"
require "rubocops/shared/no_autobump_helper"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop audits `no_autobump!` reason.
      # See the {NoAutobumpHelper} module for details of the checks.
      class NoAutobump < FormulaCop
        include NoAutobumpHelper
        extend AutoCorrector

        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          body_node = formula_nodes.body_node
          no_autobump_call = find_node_method_by_name(body_node, :no_autobump!)

          return if no_autobump_call.nil?

          reason_found = T.let(false, T::Boolean)
          reason(no_autobump_call) do |reason_node|
            reason_found = true
            offending_node(reason_node)
            audit_no_autobump(:formula, reason_node)
          end

          return if reason_found

          problem 'Add a reason for exclusion from autobump: `no_autobump! because: "..."`'
        end

        def_node_search :reason, <<~EOS
          (pair (sym :because) ${str sym})
        EOS
      end
    end
  end
end
