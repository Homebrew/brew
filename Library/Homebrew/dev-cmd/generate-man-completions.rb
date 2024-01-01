# typed: true
# frozen_string_literal: true

require "formula"
require "completions"
require "manpages"

module Homebrew
  module_function

  sig { returns(CLI::Parser) }
  def generate_man_completions_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Generate Homebrew's manpages and shell completions.
      EOS
      named_args :none
    end
  end

  def generate_man_completions
    args = generate_man_completions_args.parse

    Commands.rebuild_internal_commands_completion_list
    Manpages.regenerate_man_pages(quiet: args.quiet?)
    Completions.update_shell_completions!

    diff = system_command "git", args: [
      "-C", HOMEBREW_REPOSITORY, "diff", "--exit-code", "docs/Manpage.md", "manpages", "completions"
    ]
    if diff.status.success?
      ofail "No changes to manpage or completions."
    else
      puts "Manpage and completions updated."
    end
  end
end
