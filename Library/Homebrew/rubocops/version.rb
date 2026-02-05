# typed: strict
# frozen_string_literal: true

require "rubocops/extend/formula_cop"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop makes sure that a `version` is in the correct format.
      class Version < FormulaCop
        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          version_node = find_node_method_by_name(formula_nodes.body_node, :version)
          return unless version_node

          version = string_content(parameters(version_node).first)

          problem "Version is set to an empty string" if version.empty?

          problem "Version #{version} should not have a leading 'v'" if version.start_with?("v")

          return unless version.match?(/_\d+$/)

          problem "Version #{version} should not end with an underline and a number"
        end
      end
    end
  end
end
