# typed: strict
# frozen_string_literal: true

require "rubocops/shared/simple_expression"

module RuboCop
  module Cop
    module Homebrew
      # Keep branching and multi-step computations outside interpolation.
      #
      # @example
      #   # bad
      #   "Queue: #{queue || fallback}"
      #
      #   # good
      #   selected_queue = queue || fallback
      #   "Queue: #{selected_queue}"
      class SimpleInterpolation < Base
        include SimpleExpression

        MSG = "Move this expression outside the interpolation."

        sig { params(node: RuboCop::AST::Node).void }
        def on_begin(node)
          return unless node.loc_is?(:begin, '#{')
          return if node.children.empty?

          add_offense(node) if excessive_logic?(node)
        end
      end
    end
  end
end
