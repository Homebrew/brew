# typed: strict
# frozen_string_literal: true

require "abstract_subcommand"

require "services/cli"
module Homebrew
  module Cmd
    class Services < Homebrew::AbstractCommand
      class RestartSubcommand < Homebrew::AbstractSubcommand
        subcommand_args aliases: %w[relaunch reload r] do
          usage_banner <<~EOS
            [`sudo`] `brew services restart` (<formula>|`--all`) [`--file=`]:
            Stop (if necessary) and start the service <formula> immediately and register it to launch at login (or boot).
          EOS
          named_args :service
          flag "--file=",
               description: "Use the service file from this location to `start` the service."
          switch "--all",
                 description: "Restart all services."
        end

        sig { override.void }
        def run
          Homebrew::Services::Cli.check!(targets)

          ran = []
          started = []
          targets.each do |service|
            if service.loaded? && !service.service_file_present?
              ran << service
            else
              # group not-started services with started ones for restart
              started << service
            end
            Homebrew::Services::Cli.stop([service], verbose: args.verbose?) if service.loaded?
          end

          Homebrew::Services::Cli.run(targets, args.file, verbose: args.verbose?) if ran.present?
          Homebrew::Services::Cli.start(started, args.file, verbose: args.verbose?) if started.present?
        end

        # NOTE: The restart command is used to update service files
        # after a package gets updated through `brew upgrade`.
        # This works by removing the old file with `brew services stop`
        # and installing the new one with `brew services start|run`.
      end
    end
  end
end
