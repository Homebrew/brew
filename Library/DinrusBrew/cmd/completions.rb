# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "completions"

module DinrusBrew
  module Cmd
    class CompletionsCmd < AbstractCommand
      cmd_args do
        description <<~EOS
          Control whether DinrusBrew automatically links external tap shell completion files.
          Read more at <https://docs.brew.sh/Shell-Completion>.

          `brew completions` [`state`]:
          Display the current state of DinrusBrew's completions.

          `brew completions` (`link`|`unlink`):
          Link or unlink DinrusBrew's completions.
        EOS

        named_args %w[state link unlink], max: 1
      end

      sig { override.void }
      def run
        case args.named.first
        when nil, "state"
          if Completions.link_completions?
            puts "Completions are linked."
          else
            puts "Completions are not linked."
          end
        when "link"
          Completions.link!
          puts "Completions are now linked."
        when "unlink"
          Completions.unlink!
          puts "Completions are no longer linked."
        else
          raise UsageError, "unknown subcommand: #{args.named.first}"
        end
      end
    end
  end
end
