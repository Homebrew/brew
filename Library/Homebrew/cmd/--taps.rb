# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "shell_command"

module Homebrew
  module Cmd
    class Taps < AbstractCommand
      include ShellCommand

      sig { override.returns(String) }
      def self.command_name = "--taps"

      cmd_args do
        description <<~EOS
          Display the path to Homebrew’s Taps directory.
        EOS
      end
    end
  end
end
