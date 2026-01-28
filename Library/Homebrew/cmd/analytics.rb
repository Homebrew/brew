# typed: strict
# frozen_string_literal: true

require "abstract_command"

module Homebrew
  module Cmd
    class Analytics < AbstractCommand
      cmd_args do
        description <<~EOS
          Control Homebrew's anonymous aggregate user behaviour analytics.
          Read more at <https://docs.brew.sh/Analytics>.

          `brew analytics` [`state`]:
          Display the current state of Homebrew's analytics.

          `brew analytics` (`on`|`off`):
          Turn Homebrew's analytics on or off respectively.
        EOS

        named_args %w[state on off regenerate-uuid], max: 1
      end

      sig { override.void }
      def run
        case args.named.first
        when nil, "state"
          if Utils::Analytics.disabled?
            puts "InfluxDB analytics are disabled."
          else
            puts "InfluxDB analytics are enabled."
          end
          puts "Google Analytics were destroyed."
        when "on"
          Utils::Analytics.enable!
        when "off"
          Utils::Analytics.disable!
        when "regenerate-uuid"
          Utils::Analytics.delete_uuid!
          opoo "Homebrew no longer uses an analytics UUID so this has been deleted!"
          puts "brew analytics regenerate-uuid is no longer necessary."
        else
          raise UsageError, "unknown subcommand: #{args.named.first}"
        end
      end
    end
  end
end
