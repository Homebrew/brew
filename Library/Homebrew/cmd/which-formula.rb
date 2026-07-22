# typed: strict
# frozen_string_literal: true

# License: MIT
# The license text can be found in Library/Homebrew/command-not-found/LICENSE

require "abstract_command"
require "api"
require "shell_command"

module Homebrew
  module Cmd
    class WhichFormula < AbstractCommand
      # @api internal
      ENDPOINT = "internal/executables.txt"

      include ShellCommand

      cmd_args do
        description <<~EOS
          Show which formula(e) provides the given command.
        EOS
        switch "--explain",
               description: "Output explanation of how to get <command> by installing one of the providing formulae."
        named_args :command, min: 1
      end
    end
  end
end
