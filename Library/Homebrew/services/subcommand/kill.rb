# typed: strict
# frozen_string_literal: true

require "abstract_subcommand"

require "services/cli"
module Homebrew
  module Cmd
    class Services < Homebrew::AbstractCommand
      class KillSubcommand < Homebrew::AbstractSubcommand
        subcommand_args aliases: ["k"] do
          usage_banner <<~EOS
            [`sudo`] `brew services kill` (<formula>|`--all`):
            Stop the service <formula> immediately but keep it registered to launch at login (or boot).
          EOS
          named_args :service
          switch "--all",
                 description: "Stop all services immediately but keep them registered to launch at login (or boot)."
        end

        sig { override.void }
        def run
          Homebrew::Services::Cli.check!(targets)
          Homebrew::Services::Cli.kill(targets, verbose: args.verbose?)
        end
      end
    end
  end
end
