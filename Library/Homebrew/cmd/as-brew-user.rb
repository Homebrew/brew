# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "shell_command"

module Homebrew
  module Cmd
    # Dispatches commands as the Homebrew prefix owner.
    class AsBrewUser < AbstractCommand
      include ShellCommand

      cmd_args do
        usage_banner <<~EOS
          `as-brew-user` <command> [<args> ...]

          Run a Homebrew command as the owner of `HOMEBREW_PREFIX` on macOS or Linux.

          Use this in administrative scripts and scheduled jobs to manage an
          existing installation, including when no user is logged in.

          Uses the owner's home and a clean environment, then loads `brew.env`
          for that account. Changing users requires permission to use `sudo` or an
          already-root process; running as the owner does not. When `sudo` is
          disabled or unavailable, root can switch users directly.

          When invoked with `sudo`, this command trusts the Homebrew prefix owner
          to run arbitrary code as root: they can modify `brew` itself and the code
          it loads before switching users. Only use `sudo` if you trust the prefix owner.

          Use `brew as-brew-user install --yes` <formula> for unattended installation.
          On macOS, use `as-console-user` to select the active desktop user instead.
        EOS

        named_args min: 1
      end
    end
  end
end
