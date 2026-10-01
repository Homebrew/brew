# typed: strict
# frozen_string_literal: true

require "abstract_subcommand"

require "services/cli"
module Homebrew
  module Cmd
    class Services < Homebrew::AbstractCommand
      class StartSubcommand < Homebrew::AbstractSubcommand
        subcommand_args aliases: %w[launch load s l] do
          usage_banner <<~EOS
            [`sudo`] `brew services start` (<formula>|`--all`) [`--file=`]:
            Start the service <formula> immediately and register it to launch at login (or boot).
          EOS
          named_args :service
          flag "--file=",
               description: "Use the service file from this location to `start` the service."
          switch "--all",
                 description: "Start all services and register them to launch at login (or boot)."
        end

        sig { override.void }
        def run
          Homebrew::Services::Cli.check!(targets)
          Homebrew::Services::Cli.start(targets, args.file, verbose: args.verbose?)
        end
      end
    end
  end
end
