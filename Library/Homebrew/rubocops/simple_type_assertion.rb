# typed: strict
# frozen_string_literal: true

require "rubocops/shared/simple_expression"

module RuboCop
  module Cop
    module Homebrew
      # Keep branching, operators and multi-step computations outside Sorbet type assertions.
      #
      # @example
      #   # bad
      #   queue = T.let(dry_run ? nil : DownloadQueue.new, T.nilable(DownloadQueue))
      #
      #   # good
      #   queue = T.let(nil, T.nilable(DownloadQueue))
      #   queue ||= DownloadQueue.new unless dry_run
      class SimpleTypeAssertion < Base
        include SimpleExpression

        MSG = "Move this expression outside `T.%<method>s`."
        RESTRICT_ON_SEND = [:let, :cast].freeze

        sig { params(node: RuboCop::AST::SendNode).void }
        def on_send(node)
          return if node.receiver&.const_name != "T"

          value = node.first_argument
          add_offense(value, message: format(MSG, method: node.method_name)) if value && excessive_logic?(value)
        end
        alias on_csend on_send
      end
    end
  end
end
