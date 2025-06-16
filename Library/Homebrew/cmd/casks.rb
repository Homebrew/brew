# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "shell_command"

# This Ruby command exists to allow generation of completions for the Bash
# version. It is not meant to be run.
module Homebrew
  module Cmd
    class Casks < AbstractCommand
      include ShellCommand

      cmd_args do
        description "List all locally installable casks including short names."
      end
    end
  end
end
