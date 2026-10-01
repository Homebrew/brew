# typed: strict
# frozen_string_literal: true

require "abstract_subcommand"
require "completions"

module Homebrew
  module Cmd
    class CompletionsCmd < Homebrew::AbstractCommand
      class UnlinkSubcommand < Homebrew::AbstractSubcommand
        subcommand_args do
          usage_banner <<~EOS
            `brew completions unlink`:
            Unlink Homebrew's completions.
          EOS
          named_args :none
        end

        sig { override.void }
        def run
          Completions.unlink!
          puts "Completions are no longer linked."
        end
      end
    end
  end
end
