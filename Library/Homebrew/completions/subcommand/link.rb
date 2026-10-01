# typed: strict
# frozen_string_literal: true

require "abstract_subcommand"
require "completions"

module Homebrew
  module Cmd
    class CompletionsCmd < Homebrew::AbstractCommand
      class LinkSubcommand < Homebrew::AbstractSubcommand
        subcommand_args do
          usage_banner <<~EOS
            `brew completions link`:
            Link Homebrew's completions.
          EOS
          named_args :none
        end

        sig { override.void }
        def run
          Completions.link!
          puts "Completions are now linked."
        end
      end
    end
  end
end
