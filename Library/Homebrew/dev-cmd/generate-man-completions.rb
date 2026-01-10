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

        switch "--no-exit-code", description: "Exit with code 0 even if no changes were made."

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
        status, message = if diff.status.success?
          [:failure, "No changes to manpage or completions."]
        elsif /1 file changed, 1 insertion\(\+\), 1 deletion\(-\).*-\.TH "BREW" "1" "\w+ \d+"/m.match?(diff.stdout)
          [:failure, "No changes to manpage or completions other than the date."]
        else
          [:success, "Manpage and completions updated."]
        end

        if status == :failure && !args.no_exit_code?
          ofail message
        else
          puts message
        end
      end
    end
  end
end
