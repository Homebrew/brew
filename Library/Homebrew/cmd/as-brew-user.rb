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

          Uses the owner's home and a clean environment. Changing users requires
          permission to use `sudo` or an already-root process; running as the
          owner does not. When `sudo` is disabled or unavailable, root can switch
          users directly.
        EOS

        named_args min: 1
      end
    end
  end
end
