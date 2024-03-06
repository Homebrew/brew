# typed: true
# frozen_string_literal: true

require "rubocops/extend/formula_cop"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop makes sure that a `version` is in the correct format.
      class Version < FormulaCop
        def audit_formula(_node, _class_node, _parent_class_node, body_node)
          version_node = find_node_method_by_name(body_node, :version)
          return unless version_node

          version = string_content(parameters(version_node).first)

          problem "version is set to an empty string" if version.empty?

          problem "version #{version} should not have a leading 'v'" if version.start_with?("v")

          return unless version.match?(/_\d+$/)

          problem "version #{version} should not end with an underline and a number"
        end
      end
    end
  end
end
