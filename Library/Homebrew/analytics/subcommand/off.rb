# typed: strict
# frozen_string_literal: true

require "abstract_subcommand"
require "utils/analytics"

module Homebrew
  module Cmd
    class Analytics < Homebrew::AbstractCommand
      class OffSubcommand < Homebrew::AbstractSubcommand
        subcommand_args do
          usage_banner <<~EOS
            `brew analytics off`:
            Turn Homebrew's analytics off.
          EOS
          named_args :none
        end

        sig { override.void }
        def run
          Utils::Analytics.disable!
        end
      end
    end
  end
end
