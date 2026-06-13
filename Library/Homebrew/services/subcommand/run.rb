# typed: strict
# frozen_string_literal: true

require "abstract_subcommand"

require "services/cli"
module Homebrew
  module Cmd
    class Services < Homebrew::AbstractCommand
      class RunSubcommand < Homebrew::AbstractSubcommand
        subcommand_args do
          usage_banner <<~EOS
            [`sudo`] `brew services run` (<formula>|`--all`) [`--file=`]:
            Run the service <formula> without registering to launch at login (or boot).
          EOS
          named_args :service
          flag "--file=",
               description: "Use the service file from this location to `run` the service."
          switch "--all",
                 description: "Run all services without registering them to launch at login (or boot)."
        end

        sig { override.void }
        def run
          Homebrew::Services::Cli.check!(targets)
          Homebrew::Services::Cli.run(targets, args.file, verbose: args.verbose?)
        end
      end
    end
  end
end
