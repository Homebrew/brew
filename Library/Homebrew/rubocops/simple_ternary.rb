# typed: strict
# frozen_string_literal: true

require "rubocops/shared/simple_expression"

module RuboCop
  module Cop
    module Homebrew
      # Keep the condition and both branches of a ternary simple.
      #
      # @example
      #   # bad
      #   ready? && enabled? ? queue : fallback
      #
      #   # good
      #   if ready? && enabled?
      #     queue
      #   else
      #     fallback
      #   end
      class SimpleTernary < Base
        include SimpleExpression

        MSG = "Use `if`/`else` for this complex ternary."

        sig { params(node: RuboCop::AST::IfNode).void }
        def on_if(node)
          return unless node.ternary?

          node.each_child_node do |part|
            add_offense(part) if excessive_logic?(part)
          end
        end
      end
    end
  end
end
