# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module RuboCop
  module Cop
    module Homebrew
      # This cop restricts usage of `IO.read` functions for security reasons.
      class IORead < Base
        MSG = "The use of `IO.%<method>s` is a security risk."

        RESTRICT_ON_SEND = [:read, :readlines].freeze

        def on_send(node)
          return if node.receiver != s(:const, nil, :IO)
          return if safe?(node.arguments.first)

          add_offense(node, message: format(MSG, method: node.method_name))
        end

        private

        def safe?(node)
          if node.str_type?
            !node.str_content.empty? && !node.str_content.start_with?("|")
          elsif node.dstr_type? || (node.send_type? && node.method?(:+))
            safe?(node.children.first)
          else
            false
          end
        end
      end
    end
  end
end
