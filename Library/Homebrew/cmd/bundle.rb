# typed: strict
# frozen_string_literal: true

require "abstract_command"

module Homebrew
  module Cmd
    class Bundle < AbstractCommand
      cmd_args do
        usage_banner <<~EOS
          `bundle` [<subcommand>]

          Bundler for non-Ruby dependencies from Homebrew, Homebrew Cask, Mac App Store, Whalebrew and Visual Studio Code (and forks/variants).

          `brew bundle` [`install`]:
          Install and upgrade (by default) all dependencies from the `Brewfile`.

          You can specify the `Brewfile` location using `--file` or by setting the `$HOMEBREW_BUNDLE_FILE` environment variable.

          You can skip the installation of dependencies by adding space-separated values to one or more of the following environment variables: `$HOMEBREW_BUNDLE_BREW_SKIP`, `$HOMEBREW_BUNDLE_CASK_SKIP`, `$HOMEBREW_BUNDLE_MAS_SKIP`, `$HOMEBREW_BUNDLE_WHALEBREW_SKIP`, `$HOMEBREW_BUNDLE_TAP_SKIP`.

          `brew bundle upgrade`:
          Shorthand for `brew bundle install --upgrade`.

          `brew bundle dump`:
          Write all installed casks/formulae/images/taps into a `Brewfile` in the current directory or to a custom file specified with the `--file` option.

          `brew bundle cleanup`:
          Uninstall all dependencies not present in the `Brewfile`.

          This workflow is useful for maintainers or testers who regularly install lots of formulae.

          Unless `--force` is passed, this returns a 1 exit code if anything would be removed.

          `brew bundle check`:
          Check if all dependencies present in the `Brewfile` are installed.

          This provides a successful exit code if everything is up-to-date, making it useful for scripting.

          `brew bundle list`:
          List all dependencies present in the `Brewfile`.

          By default, only Homebrew formula dependencies are listed.

          `brew bundle edit`:
          Edit the `Brewfile` in your editor.

          `brew bundle add` <name> [...]:
          Add entries to your `Brewfile`. Adds formulae by default. Use `--cask`, `--tap`, `--whalebrew` or `--vscode` to add the corresponding entry instead.

          `brew bundle remove` <name> [...]:
          Remove entries that match `name` from your `Brewfile`. Use `--formula`, `--cask`, `--tap`, `--mas`, `--whalebrew` or `--vscode` to remove only entries of the corresponding type. Passing `--formula` also removes matches against formula aliases and old formula names.

          `brew bundle exec` [--check] <command>:
          Run an external command in an isolated build environment based on the `Brewfile` dependencies.

          This sanitized build environment ignores unrequested dependencies, which makes sure that things you didn't specify in your `Brewfile` won't get picked up by commands like `bundle install`, `npm install`, etc. It will also add compiler flags which will help with finding keg-only dependencies like `openssl`, `icu4c`, etc.

          `brew bundle sh` [--check]:
          Run your shell in a `brew bundle exec` environment.

          `brew bundle env` [--check]:
          Print the environment variables that would be set in a `brew bundle exec` environment.
        EOS
        flag "--file=",
             description: "Read from or write to the `Brewfile` from this location. " \
                          "Use `--file=-` to pipe to stdin/stdout."
        switch "--global",
               description: "Read from or write to the `Brewfile` from `$HOMEBREW_BUNDLE_FILE_GLOBAL` (if set), " \
                            "`${XDG_CONFIG_HOME}/homebrew/Brewfile` (if `$XDG_CONFIG_HOME` is set), " \
                            "`~/.homebrew/Brewfile` or `~/.Brewfile` otherwise."
        switch "-v", "--verbose",
               description: "`install` prints output from commands as they are run. " \
                            "`check` lists all missing dependencies."
        switch "--no-upgrade",
               description: "`install` does not run `brew upgrade` on outdated dependencies. " \
                            "`check` does not check for outdated dependencies. " \
                            "Note they may still be upgraded by `brew install` if needed.",
               env:         :bundle_no_upgrade
        switch "--upgrade",
               description: "`install` runs `brew upgrade` on outdated dependencies, " \
                            "even if `$HOMEBREW_BUNDLE_NO_UPGRADE` is set."
        flag "--upgrade-formulae=", "--upgrade-formula=",
             description: "`install` runs `brew upgrade` on any of these comma-separated formulae, " \
                          "even if `$HOMEBREW_BUNDLE_NO_UPGRADE` is set."
        switch "--install",
               description: "Run `install` before continuing to other operations e.g. `exec`."
        switch "--services",
               description: "Temporarily start services while running the `exec` or `sh` command.",
               env:         :bundle_services
        switch "-f", "--force",
               description: "`install` runs with `--force`/`--overwrite`. " \
                            "`dump` overwrites an existing `Brewfile`. " \
                            "`cleanup` actually performs its cleanup operations."
        switch "--cleanup",
               description: "`install` performs cleanup operation, same as running `cleanup --force`.",
               env:         [:bundle_install_cleanup, "--global"]
        switch "--all",
               description: "`list` all dependencies."
        switch "--formula", "--brews",
               description: "`list`, `dump` or `cleanup` Homebrew formula dependencies."
        switch "--cask", "--casks",
               description: "`list`, `dump` or `cleanup` Homebrew cask dependencies."
        switch "--tap", "--taps",
               description: "`list`, `dump` or `cleanup` Homebrew tap dependencies."
        switch "--mas",
               description: "`list` or `dump` Mac App Store dependencies."
        switch "--whalebrew",
               description: "`list` or `dump` Whalebrew dependencies."
        switch "--vscode",
               description: "`list`, `dump` or `cleanup` VSCode (and forks/variants) extensions."
        switch "--no-vscode",
               description: "`dump` without VSCode (and forks/variants) extensions.",
               env:         :bundle_dump_no_vscode
        switch "--describe",
               description: "`dump` adds a description comment above each line, unless the " \
                            "dependency does not have a description.",
               env:         :bundle_dump_describe
        switch "--no-restart",
               description: "`dump` does not add `restart_service` to formula lines."
        switch "--zap",
               description: "`cleanup` casks using the `zap` command instead of `uninstall`."
        switch "--check",
               description: "Check that all dependencies in the Brewfile are installed before " \
                            "running `exec`, `sh`, or `env`."

        conflicts "--all", "--no-vscode"
        conflicts "--vscode", "--no-vscode"
        conflicts "--install", "--upgrade"

        named_args %w[install dump cleanup check exec list sh env edit]
      end

      BUNDLE_EXEC_COMMANDS = %w[exec sh env].freeze

      sig { override.void }
      def run
        # Keep this inside `run` to keep --help fast.
        require "bundle"

        # Don't want to ask for input in Bundle
        ENV["HOMEBREW_ASK"] = nil

        subcommand = args.named.first.presence
        if %w[exec add remove].exclude?(subcommand) && args.named.size > 1
          raise UsageError, "This command does not take more than 1 subcommand argument."
        end

        if args.check? && BUNDLE_EXEC_COMMANDS.exclude?(subcommand)
          raise UsageError, "`--check` can be used only with #{BUNDLE_EXEC_COMMANDS.join(", ")}."
        end

        global = args.global?
        file = args.file
        no_upgrade = if args.upgrade? || subcommand == "upgrade"
          false
        else
          args.no_upgrade?.present?
        end
        verbose = args.verbose?
        force = args.force?
        zap = args.zap?
        Homebrew::Bundle.upgrade_formulae = args.upgrade_formulae

        no_type_args = !args.brews? && !args.casks? && !args.taps? && !args.mas? && !args.whalebrew? && !args.vscode?

        if args.install?
          if [nil, "install", "upgrade"].include?(subcommand)
            raise UsageError, "`--install` cannot be used with `install`, `upgrade` or no subcommand."
          end

          require "bundle/commands/install"
          redirect_stdout($stderr) do
            Homebrew::Bundle::Commands::Install.run(global:, file:, no_upgrade:, verbose:, force:, quiet: true)
          end
        end

        case subcommand
        when nil, "install", "upgrade"
          require "bundle/commands/install"
          Homebrew::Bundle::Commands::Install.run(global:, file:, no_upgrade:, verbose:, force:, quiet: args.quiet?)

          cleanup = if ENV.fetch("HOMEBREW_BUNDLE_INSTALL_CLEANUP", nil)
            args.global?
          else
            args.cleanup?
          end

          if cleanup
            require "bundle/commands/cleanup"
            Homebrew::Bundle::Commands::Cleanup.run(
              global:, file:, zap:,
              force:  true,
              dsl:    Homebrew::Bundle::Commands::Install.dsl
            )
          end
        when "dump"
          vscode = if args.no_vscode?
            false
          elsif args.vscode?
            true
          else
            no_type_args
          end

          require "bundle/commands/dump"
          Homebrew::Bundle::Commands::Dump.run(
            global:, file:, force:,
            describe:   args.describe?,
            no_restart: args.no_restart?,
            taps:       args.taps? || no_type_args,
            brews:      args.brews? || no_type_args,
            casks:      args.casks? || no_type_args,
            mas:        args.mas? || no_type_args,
            whalebrew:  args.whalebrew? || no_type_args,
            vscode:
          )
        when "edit"
          require "bundle/brewfile"
          exec_editor(Homebrew::Bundle::Brewfile.path(global:, file:))
        when "cleanup"
          require "bundle/commands/cleanup"
          Homebrew::Bundle::Commands::Cleanup.run(
            global:, file:, force:, zap:,
            brews:  args.brews? || no_type_args,
            casks:  args.casks? || no_type_args,
            taps:   args.taps? || no_type_args,
            vscode: args.vscode? || no_type_args
          )
        when "check"
          require "bundle/commands/check"
          Homebrew::Bundle::Commands::Check.run(global:, file:, no_upgrade:, verbose:)
        when "list"
          require "bundle/commands/list"
          Homebrew::Bundle::Commands::List.run(
            global:,
            file:,
            brews:     args.brews? || args.all? || no_type_args,
            casks:     args.casks? || args.all?,
            taps:      args.taps? || args.all?,
            mas:       args.mas? || args.all?,
            whalebrew: args.whalebrew? || args.all?,
            vscode:    args.vscode? || args.all?,
          )
        when "add", "remove"
          # We intentionally omit the `s` from `brews`, `casks`, and `taps` for ease of handling later.
          type_hash = {
            brew:      args.brews?,
            cask:      args.casks?,
            tap:       args.taps?,
            mas:       args.mas?,
            whalebrew: args.whalebrew?,
            vscode:    args.vscode?,
            none:      no_type_args,
          }
          selected_types = type_hash.select { |_, v| v }.keys
          raise UsageError, "`#{subcommand}` supports only one type of entry at a time." if selected_types.count != 1

          _, *named_args = args.named
          if subcommand == "add"
            type = case (t = selected_types.first)
            when :none then :brew
            when :mas then raise UsageError, "`add` does not support `--mas`."
            else t
            end

            require "bundle/commands/add"
            Homebrew::Bundle::Commands::Add.run(*named_args, type:, global:, file:)
          else
            require "bundle/commands/remove"
            Homebrew::Bundle::Commands::Remove.run(*named_args, type: selected_types.first, global:, file:)
          end
        when *BUNDLE_EXEC_COMMANDS
          named_args = case subcommand
          when "exec"
            _subcommand, *named_args = args.named
            named_args
          when "sh"
            ["sh"]
          when "env"
            ["env"]
          end
          require "bundle/commands/exec"
          Homebrew::Bundle::Commands::Exec.run(*named_args, global:, file:, subcommand:, services: args.services?)
        else
          raise UsageError, "unknown subcommand: #{subcommand}"
        end
      end
    end
  end
end
