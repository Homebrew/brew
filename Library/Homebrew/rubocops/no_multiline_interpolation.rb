# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Homebrew
      # Keep each interpolation on one line so the surrounding text is easy to read.
      #
      # @example
      #   # bad
      #   "HTTP #{response.dig(:redirect,
      #                        :status)}"
      #
      #   # good
      #   redirect = response[:redirect]
      #   "HTTP #{redirect[:status]}"
      class NoMultilineInterpolation < Base
        MSG = "Keep each interpolation on one line."

        sig { params(node: RuboCop::AST::Node).void }
        def on_begin(node)
          add_offense(node.loc.begin) if node.loc_is?(:begin, '#{') && node.multiline?
        end
      end
    end
  end
end
