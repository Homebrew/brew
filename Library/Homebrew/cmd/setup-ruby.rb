# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "shell_command"

module Homebrew
  module Cmd
    class SetupRuby < AbstractCommand
      include ShellCommand

      cmd_args do
        description <<~EOS
          Installs and configures Homebrew's Ruby. If `command` is passed, it will only run Bundler if necessary for that command.
        EOS

        named_args :command
      end
    end
  end
end
