# typed: strict
# frozen_string_literal: true

require "abstract_subcommand"
require "utils/analytics"

module Homebrew
  module Cmd
    class Analytics < Homebrew::AbstractCommand
      class StateSubcommand < Homebrew::AbstractSubcommand
        subcommand_args default: true do
          usage_banner <<~EOS
            `brew analytics` [`state`]:
            Display the current state of Homebrew's analytics.
          EOS
          named_args :none
        end

        sig { override.void }
        def run
          if Utils::Analytics.disabled?
            puts "InfluxDB analytics are disabled."
          else
            puts "InfluxDB analytics are enabled."
          end
          puts "Google Analytics were destroyed."
        end
      end
    end
  end
end
