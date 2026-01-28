# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "shell_command"

module Homebrew
  module Cmd
    class Update < AbstractCommand
      include ShellCommand

      cmd_args do
        description <<~EOS
          Fetch the newest version of Homebrew and all formulae from GitHub using `git`(1) and perform any necessary migrations.
        EOS
        switch "--merge",
               description: "Use `git merge` to apply updates (rather than `git rebase`)."
        switch "--auto-update",
               description: "Run on auto-updates (e.g. before `brew install`). Skips some slower steps."
        switch "-f", "--force",
               description: "Always do a slower, full update check (even if unnecessary)."
        switch "-q", "--quiet",
               description: "Make some output more quiet."
        switch "-v", "--verbose",
               description: "Print the directories checked and `git` operations performed."
        switch "-d", "--debug",
               description: "Display a trace of all shell commands as they are executed."
      end
    end
  end
end
