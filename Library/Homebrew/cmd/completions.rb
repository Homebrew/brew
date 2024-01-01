# typed: strict
# frozen_string_literal: true

require "cli/parser"
require "completions"

module Homebrew
  module_function

  sig { returns(CLI::Parser) }
  def completions_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Control whether Homebrew automatically links external tap shell completion files.
        Read more at <https://docs.brew.sh/Shell-Completion>.

        `brew completions` [`state`]:
        Display the current state of Homebrew's completions.

        `brew completions` (`link`|`unlink`):
        Link or unlink Homebrew's completions.
      EOS

      named_args %w[state link unlink], max: 1
    end
  end

  sig { void }
  def completions
    args = completions_args.parse

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
