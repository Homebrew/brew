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
      ENDPOINT = "internal/executables.txt"
      DATABASE_FILE = T.let((Homebrew::API::HOMEBREW_CACHE_API/ENDPOINT).freeze, Pathname)

      include ShellCommand

      cmd_args do
        description <<~EOS
          Show which formula(e) provides the given command.
        EOS
        switch "--explain",
               description: "Output explanation of how to get <command> by installing one of the providing formulae."
        switch "--skip-update",
               description: "Skip updating the executables database if any version exists on disk, no matter how old."
        named_args :command, min: 1
      end
    end
  end
end
