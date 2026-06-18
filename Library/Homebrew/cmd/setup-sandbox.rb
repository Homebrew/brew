# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "shell_command"

module Homebrew
  module Cmd
    class SetupSandbox < AbstractCommand
      include ShellCommand

      cmd_args do
        description <<~EOS
          Run any necessary commands to setup the Homebrew sandbox.
          Must be run with `sudo`. Currently a no-op on non-Linux.
        EOS
      end
    end
  end
end
