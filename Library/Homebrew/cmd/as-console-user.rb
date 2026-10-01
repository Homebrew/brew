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

          Run a Homebrew command as the active macOS console user.

          This is intended for MDM, Munki and Jamf workflows where `brew` is
          invoked as root but Homebrew operations should run as the logged-in
          console user. Uses their home and a clean environment, dispatching
          through `HOMEBREW_BREW_FILE`. Use `as-brew-user` to select the prefix owner.
          When `sudo` is disabled or unavailable, root can switch users directly.
        EOS

        named_args min: 1
      end
    end
  end
end
