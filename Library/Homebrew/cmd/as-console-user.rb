# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "shell_command"

module Homebrew
  module Cmd
    class AsConsoleUser < AbstractCommand
      include ShellCommand

      cmd_args do
        usage_banner <<~EOS
          `as-console-user` <command> [<args> ...]

          Run a Homebrew command as the user logged in to the macOS desktop.

          Use this from administrative scripts when the desktop user manages
          Homebrew, for example `brew as-console-user install --yes` <formula>.
          Fails if no supported desktop user is logged in.

          Uses the user's home and a clean environment, then loads `brew.env` for
          that account. Uses `sudo` when enabled and available; root can also switch
          users when `sudo` is disabled or unavailable.

          When invoked with `sudo`, this command trusts the Homebrew prefix owner
          to run arbitrary code as root: they can modify `brew` itself and the code
          it loads before switching users. Only use `sudo` if you trust the prefix owner.

          Use `as-brew-user` to select the installation's owner on macOS or Linux,
          including when no user is logged in.
        EOS

        named_args min: 1
      end
    end
  end
end
