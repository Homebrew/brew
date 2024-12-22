# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"
require "completions"
require "manpages"
require "system_command"

module Homebrew
  module DevCmd
    class GenerateManCompletions < AbstractCommand
      include SystemCommand::Mixin

      cmd_args do
        description <<~EOS
          Generate Homebrew's manpages and shell completions.
        EOS
        named_args :none
      end

      sig { override.void }
      def run
        Homebrew.install_bundler_gems!(groups: ["man"])

        Commands.rebuild_internal_commands_completion_list
        Manpages.regenerate_man_pages(quiet: args.quiet?)
        Completions.update_shell_completions!

        diff = system_command "git", args: [
          "-C", HOMEBREW_REPOSITORY,
          "diff", "--shortstat", "--patch", "--exit-code", "docs/Manpage.md", "manpages", "completions"
        ]
        if diff.status.success?
          ofail "No changes to manpage or completions."
        elsif /1 file changed, 1 insertion\(\+\), 1 deletion\(-\).*-\.TH "BREW" "1" "\w+ \d+"/m.match?(diff.stdout)
          ofail "No changes to manpage or completions other than the date."
        else
          puts "Manpage and completions updated."
        end
      end
    end
  end
end
