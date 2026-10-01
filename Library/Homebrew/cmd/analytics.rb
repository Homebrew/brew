# typed: strict
# frozen_string_literal: true

require "abstract_command"

module Homebrew
  module Cmd
    class Analytics < AbstractCommand
      require "analytics/subcommand"

      cmd_args do
        usage_banner <<~EOS
          `analytics` [<subcommand>]

          Control Homebrew's anonymous aggregate user behaviour analytics.
          Read more at <https://docs.brew.sh/Analytics>.
        EOS

        Homebrew::AbstractSubcommand.define_all(self, command: Homebrew::Cmd::Analytics)
      end

      sig { override.void }
      def run
        Homebrew::Cmd::Analytics.dispatch(args)
      end
    end
  end
end
