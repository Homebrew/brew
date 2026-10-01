# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Homebrew
      # Disallows shell command literals so command execution uses an explicit process API.
      class NoCommandLiteral < Base
        MSG = "Use an explicit process API instead of a command literal. " \
              "Pass arguments separately unless shell syntax is intentional."

        RESTRICT_ON_SEND = [:`].freeze

        sig { params(node: RuboCop::AST::Node).void }
        def on_xstr(node)
          add_offense(node)
        end

        sig { params(node: RuboCop::AST::SendNode).void }
        def on_send(node)
          add_offense(node)
        end
      end
    end
  end
end
