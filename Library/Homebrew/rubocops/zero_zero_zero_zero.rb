# typed: strict
# frozen_string_literal: true

require "rubocops/extend/formula_cop"

module RuboCop
  module Cop
    module FormulaAudit
      # This cop audits the use of 0.0.0.0 in formulae.
      # 0.0.0.0 should not be used outside of test do blocks as it can be a security risk.
      class ZeroZeroZeroZero < FormulaCop
        sig { override.params(formula_nodes: FormulaNodes).void }
        def audit_formula(formula_nodes)
          return if formula_tap != "homebrew-core"

          body_node = formula_nodes.body_node
          return if body_node.nil?

          test_block = find_block(body_node, :test)

          # Find all string literals in the formula
          body_node.each_descendant(:str) do |str_node|
            content = string_content(str_node)
            next unless content.include?("0.0.0.0")
            next if test_block && str_node.ancestors.any?(test_block)

            next if valid_ip_range?(content)

            offending_node(str_node)
            problem "Do not use 0.0.0.0 as it can be a security risk."
          end
        end

        private

        sig { params(content: String).returns(T::Boolean) }
        def valid_ip_range?(content)
          # Allow private IP ranges like 10.0.0.0, 172.16.0.0-172.31.255.255, 192.168.0.0-192.168.255.255
          return true if content.match?(/\b(?:10|172\.(?:1[6-9]|2[0-9]|3[01])|192\.168)\.\d+\.\d+\b/)
          # Allow IP range notation like 0.0.0.0-255.255.255.255
          return true if content.match?(/\b0\.0\.0\.0\s*-\s*255\.255\.255\.255\b/)

          false
        end
      end
    end
  end
end
