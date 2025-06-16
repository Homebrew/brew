# typed: strong
# frozen_string_literal: true

require "abstract_command"
require "help"

module Homebrew
  module Cmd
    class HelpCmd < AbstractCommand
      cmd_args do
        description <<~EOS
          Outputs the usage instructions for `brew` <command>.
          Equivalent to `brew --help` <command>.
        EOS
        named_args [:command]
      end

      sig { override.void }
      def run
        Help.help
      end
    end
  end
end
