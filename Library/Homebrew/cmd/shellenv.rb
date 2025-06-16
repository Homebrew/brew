# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "shell_command"

module Homebrew
  module Cmd
    class Shellenv < AbstractCommand
      include ShellCommand

      cmd_args do
        description <<~EOS
          Valid shells: bash|csh|fish|pwsh|sh|tcsh|zsh

          Print export statements. When run in a shell, this installation of Homebrew will be added to your
          `$PATH`, `$MANPATH`, and `$INFOPATH`.

          The variables `$HOMEBREW_PREFIX`, `$HOMEBREW_CELLAR` and `$HOMEBREW_REPOSITORY` are also exported to avoid
          querying them multiple times.
          To help guarantee idempotence, this command produces no output when Homebrew's `bin` and `sbin` directories
          are first and second respectively in your `$PATH`. Consider adding evaluation of this command's output to
          your dotfiles (e.g. `~/.bash_profile` or ~/.zprofile` on macOS and ~/.bashrc` or ~/.zshrc` on Linux) with:
            `eval "$(brew shellenv)"`

          The shell can be specified explicitly with a supported shell name parameter. Unknown shells will output
          POSIX exports.
        EOS

        named_args :shell
      end
    end
  end
end
