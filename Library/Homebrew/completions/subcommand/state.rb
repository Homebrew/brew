# typed: strict
# frozen_string_literal: true

require "abstract_subcommand"
require "completions"

module Homebrew
  module Cmd
    class CompletionsCmd < Homebrew::AbstractCommand
      class StateSubcommand < Homebrew::AbstractSubcommand
        subcommand_args default: true do
          usage_banner <<~EOS
            `brew completions` [`state`]:
            Display the current state of Homebrew's completions.
          EOS
          named_args :none
        end

        sig { override.void }
        def run
          if Completions.link_completions?
            puts "Completions are linked."
          else
            puts "Completions are not linked."
          end
        end
      end
    end
  end
end
