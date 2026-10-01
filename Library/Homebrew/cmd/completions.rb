# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "completions"

module Homebrew
  module Cmd
    class CompletionsCmd < AbstractCommand
      require "completions/subcommand"

      cmd_args do
        usage_banner <<~EOS
          `completions` [<subcommand>]

          Control whether Homebrew automatically links external tap shell completion files.
          Read more at <https://docs.brew.sh/Shell-Completion>.
        EOS

        Homebrew::AbstractSubcommand.define_all(self, command: Homebrew::Cmd::CompletionsCmd)
      end

      sig { override.void }
      def run
        Homebrew::Cmd::CompletionsCmd.dispatch(args)
      end
    end
  end
end
