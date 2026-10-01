# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "shell_command"

module Homebrew
  module Cmd
    class Exec < AbstractCommand
      include ShellCommand

      cmd_args do
        usage_banner <<~EOS
          `exec`, `x` [`--formulae=`<formulae>] [`--sandbox=`<path>] [`--deny-network`] [`--`] <command> [<args> ...]

          Run <command> in an environment populated by Homebrew formulae.

          If `--formulae` is passed, Homebrew installs those comma-separated
          formulae if needed, prepends their executable directories and those of
          their dependencies to `PATH` and runs <command>. This allows <command>
          to be a script path such as `./script.sh`.

          If `--formulae` is omitted, Homebrew finds a formula that provides
          <command>, installs it if needed and runs that executable.

          Example: `brew exec --formulae=jq,yq -- ./script.sh`

          Scripts can also use a shebang on systems with `env -S`:
          `#!/usr/bin/env -S brew exec --formulae=jq,yq --`
        EOS

        comma_array "--formulae",
                    description: "Comma-separated formulae to install and add to `PATH` before running " \
                                 "<command>."
        flag "--sandbox=",
             description: "Run <command> in Homebrew's sandbox, allowing writes to <path> and Homebrew's " \
                          "temporary and cache directories."
        switch "--deny-network",
               description: "Deny network access from inside the sandbox.",
               depends_on:  "--sandbox="

        named_args min: 1
      end
    end
  end
end
