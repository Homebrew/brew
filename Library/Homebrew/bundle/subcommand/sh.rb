# typed: strict
# frozen_string_literal: true

require "abstract_subcommand"

module Homebrew
  module Cmd
    class Bundle < Homebrew::AbstractCommand
      class ShSubcommand < Homebrew::AbstractSubcommand
        subcommand_args do
          usage_banner <<~EOS
            `brew bundle sh` [`--check`] [`--no-secrets`]:
            Run your shell in a `brew bundle exec` environment.
          EOS
          named_args :none
          switch "--install",
                 description: "Run `install` before starting the shell."
          switch "--services",
                 description: "Temporarily start services while running the shell.",
                 env:         :bundle_services
          switch "--check",
                 description: "Check that all dependencies in the Brewfile are installed before " \
                              "starting the shell.",
                 env:         :bundle_check
          switch "--no-secrets",
                 description: "Attempt to remove secrets from the environment before starting the shell.",
                 env:         :bundle_no_secrets
        end

        sig { override.void }
        def run
          ExecSubcommand.run_command("sh", args:, context:)
        end
      end
    end
  end
end
