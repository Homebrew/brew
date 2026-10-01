# typed: strict
# frozen_string_literal: true

require "abstract_command"

module Homebrew
  module Cmd
    class Developer < AbstractCommand
      require "developer/subcommand"

      cmd_args do
        usage_banner <<~EOS
          `developer` [<subcommand>]

          Control Homebrew's developer mode. When developer mode is enabled,
          `brew update` will update Homebrew to the latest commit on the `main`
          branch instead of the latest stable version along with some other behaviour changes.
        EOS

        Homebrew::AbstractSubcommand.define_all(self, command: Homebrew::Cmd::Developer)
      end

      sig { override.void }
      def run
        Homebrew::Cmd::Developer.dispatch(args)
      end
    end
  end
end
