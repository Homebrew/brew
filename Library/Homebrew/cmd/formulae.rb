# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "shell_command"

module Homebrew
  module Cmd
    class Formulae < AbstractCommand
      include ShellCommand

      cmd_args do
        description "List all locally installable formulae including short names."
      end
    end
  end
end
