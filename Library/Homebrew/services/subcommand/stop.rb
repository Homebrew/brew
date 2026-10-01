# typed: strict
# frozen_string_literal: true

require "abstract_subcommand"

require "services/cli"
module Homebrew
  module Cmd
    class Services < Homebrew::AbstractCommand
      class StopSubcommand < Homebrew::AbstractSubcommand
        subcommand_args aliases: %w[unload terminate term t u] do
          usage_banner <<~EOS
            [`sudo`] `brew services stop` [`--keep`] [`--no-wait`|`--max-wait=`] (<formula>|`--all`):
            Stop the service <formula> immediately and unregister it from launching at login (or boot),
            unless `--keep` is specified.
          EOS
          named_args :service
          flag   "--max-wait=",
                 description: "Wait at most this many seconds for `stop` to finish stopping a service. " \
                              "Defaults to 60. Set this to zero (0) seconds to wait indefinitely."
          switch "--no-wait",
                 description: "Don't wait for `stop` to finish stopping the service."
          switch "--keep",
                 description: "When stopped, don't unregister the service from launching at login (or boot)."
          switch "--all",
                 description: "Stop all services and unregister them from launching at login (or boot), " \
                              "unless `--keep` is specified."
        end

        sig { override.void }
        def run
          Homebrew::Services::Cli.check!(targets)
          Homebrew::Services::Cli.stop(
            targets,
            verbose:  args.verbose?,
            no_wait:  args.no_wait?,
            max_wait: args.max_wait&.to_f || 60.0,
            keep:     args.keep?,
          )
        end
      end
    end
  end
end
