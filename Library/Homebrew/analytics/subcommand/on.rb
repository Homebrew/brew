# typed: strict
# frozen_string_literal: true

require "abstract_subcommand"
require "utils/analytics"

module Homebrew
  module Cmd
    class Analytics < Homebrew::AbstractCommand
      class OnSubcommand < Homebrew::AbstractSubcommand
        subcommand_args do
          usage_banner <<~EOS
            `brew analytics on`:
            Turn Homebrew's analytics on.
          EOS
          named_args :none
        end

        sig { override.void }
        def run
          Utils::Analytics.enable!
        end
      end
    end
  end
end
