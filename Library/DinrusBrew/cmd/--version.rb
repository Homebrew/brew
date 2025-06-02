# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "shell_command"

module DinrusBrew
  module Cmd
    class Version < AbstractCommand
      include ShellCommand

      sig { override.returns(String) }
      def self.command_name = "--version"

      cmd_args do
        description <<~EOS
          Print the version numbers of DinrusBrew, DinrusBrew/homebrew-core and
          DinrusBrew/homebrew-cask (if tapped) to standard output.
        EOS
      end
    end
  end
end
