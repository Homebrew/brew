# typed: strict
# frozen_string_literal: true

module RuboCop
  module Cop
    module Homebrew
      class ShellCommandStub < Base
        MSG = "Shell command stubs must have a `.sh` counterpart."
        RESTRICT_ON_SEND = [:include].freeze

        sig { params(node: AST::SendNode).void }
        def on_send(node)
          return if node.first_argument&.const_name != "ShellCommand"

          stub_path = Pathname.new(processed_source.file_path)
          sh_cmd_path = Pathname.new("#{stub_path.dirname}/#{stub_path.basename(".rb")}.sh")
          return if sh_cmd_path.exist?

          add_offense(node)
        end
      end
    end
  end
end
