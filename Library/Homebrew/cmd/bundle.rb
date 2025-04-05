# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "abstract_subcommand"

module Homebrew
  module Cmd
    class Bundle < AbstractCommand
      include AbstractSubcommandMod
      include SubcommandDispatcher

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

          `brew bundle exec` <command>:
          Run an external command in an isolated build environment based on the `Brewfile` dependencies.

          This sanitized build environment ignores unrequested dependencies, which makes sure that things you didn't specify in your `Brewfile` won't get picked up by commands like `bundle install`, `npm install`, etc. It will also add compiler flags which will help with finding keg-only dependencies like `openssl`, `icu4c`, etc.

          `brew bundle sh`:
          Run your shell in a `brew bundle exec` environment.

          `brew bundle env`:
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
               env:         :bundle_no_upgrade,
               description: "`install` does not run `brew upgrade` on outdated dependencies. " \
                            "`check` does not check for outdated dependencies. " \
                            "Note they may still be upgraded by `brew install` if needed. " \
                            "This is enabled by default if `$HOMEBREW_BUNDLE_NO_UPGRADE` is set."
        switch "--upgrade",
               description: "`install` runs `brew upgrade` on outdated dependencies, " \
                            "even if `$HOMEBREW_BUNDLE_NO_UPGRADE` is set."
        flag "--upgrade-formulae=", "--upgrade-formula=",
             description: "`install` runs `brew upgrade` on any of these comma-separated formulae, " \
                          "even if `$HOMEBREW_BUNDLE_NO_UPGRADE` is set."
        switch "--install",
               description: "Run `install` before continuing to other operations e.g. `exec`."
        switch "--services",
               description: "Temporarily start services while running the `exec` or `sh` command."
        switch "-f", "--force",
               description: "`install` runs with `--force`/`--overwrite`. " \
                            "`dump` overwrites an existing `Brewfile`. " \
                            "`cleanup` actually performs its cleanup operations."
        switch "--cleanup",
               env:         :bundle_install_cleanup,
               description: "`install` performs cleanup operation, same as running `cleanup --force`. " \
                            "This is enabled by default if `$HOMEBREW_BUNDLE_INSTALL_CLEANUP` is set and " \
                            "`--global` is passed."
        switch "--all",
               description: "`list` all dependencies."
        switch "--formula", "--brews",
               description: "`list` or `dump` Homebrew formula dependencies."
        switch "--cask", "--casks",
               description: "`list` or `dump` Homebrew cask dependencies."
        switch "--tap", "--taps",
               description: "`list` or `dump` Homebrew tap dependencies."
        switch "--mas",
               description: "`list` or `dump` Mac App Store dependencies."
        switch "--whalebrew",
               description: "`list` or `dump` Whalebrew dependencies."
        switch "--vscode",
               description: "`list` or `dump` VSCode (and forks/variants) extensions."
        switch "--no-vscode",
               env:         :bundle_dump_no_vscode,
               description: "`dump` without VSCode (and forks/variants) extensions. " \
                            "This is enabled by default if `$HOMEBREW_BUNDLE_DUMP_NO_VSCODE` is set."
        switch "--describe",
               env:         :bundle_dump_describe,
               description: "`dump` adds a description comment above each line, unless the " \
                            "dependency does not have a description. " \
                            "This is enabled by default if `$HOMEBREW_BUNDLE_DUMP_DESCRIBE` is set."
        switch "--no-restart",
               description: "`dump` does not add `restart_service` to formula lines."
        switch "--zap",
               description: "`cleanup` casks using the `zap` command instead of `uninstall`."

        conflicts "--all", "--no-vscode"
        conflicts "--vscode", "--no-vscode"
        conflicts "--install", "--upgrade"

        named_args %w[install dump cleanup check exec list sh env edit]
      end

      # Define shared arguments that subcommands can inherit
      sig { returns(T.nilable(T.proc.void)) }
      def self.shared_args_block
        nil
      end

      sig { override.void }
      def run
        # Keep this inside `run` to keep --help fast.
        require "bundle"

        dispatch_subcommand(args.named.first.presence) || default_subcommand
      end

      sig { void }
      def default_subcommand
        InstallSubcommand.new([]).run
      end

      class InstallSubcommand < AbstractSubcommand
        cmd_args do
          flag "--file=",
               description: "Read from the `Brewfile` from this location."
          switch "--global",
                 description: "Read from the global Brewfile."
          switch "--verbose",
                 description: "Print output from commands as they are run."
          switch "--no-upgrade",
                 description: "Don't run `brew upgrade` on outdated dependencies."
          switch "--upgrade",
                 description: "Run `brew upgrade` on outdated dependencies."
          switch "--force",
                 description: "Run with `--force`/`--overwrite`."
          switch "--cleanup",
                 description: "Perform cleanup operation after installing."
          flag "--upgrade-formulae=", "--upgrade-formula=",
               description: "Run `brew upgrade` on these comma-separated formulae."
          conflicts "--no-upgrade", "--upgrade"
        end

        sig { override.void }
        def run
          require "bundle/commands/install"

          args_obj = T.unsafe(args)
          global_opt = args_obj.respond_to?(:global?) ? args_obj.global? : false
          file_opt = args_obj.respond_to?(:file) ? args_obj.file : nil
          no_upgrade_opt = args_obj.respond_to?(:no_upgrade?) && args_obj.no_upgrade? &&
                           !(args_obj.respond_to?(:upgrade?) && args_obj.upgrade?)
          verbose_opt = args_obj.respond_to?(:verbose?) ? args_obj.verbose? : false
          force_opt = args_obj.respond_to?(:force?) ? args_obj.force? : false
          quiet_opt = args_obj.respond_to?(:quiet?) ? args_obj.quiet? : false

          Homebrew::Bundle::Commands::Install.run(
            global:     global_opt,
            file:       file_opt,
            no_upgrade: no_upgrade_opt,
            verbose:    verbose_opt,
            force:      force_opt,
            quiet:      quiet_opt,
          )

          cleanup = if ENV.fetch("HOMEBREW_BUNDLE_INSTALL_CLEANUP", nil)
            global_opt
          else
            args_obj.respond_to?(:cleanup?) ? args_obj.cleanup? : false
          end

          return unless cleanup

          require "bundle/commands/cleanup"
          Homebrew::Bundle::Commands::Cleanup.run(
            global: global_opt,
            file:   file_opt,
            zap:    false,
            force:  true,
            dsl:    Homebrew::Bundle::Commands::Install.dsl,
          )
        end
      end

      class UpgradeSubcommand < AbstractSubcommand
        cmd_args do
          flag "--file=",
               description: "Read from the `Brewfile` from this location."
          switch "--global",
                 description: "Read from the global Brewfile."
          switch "--verbose",
                 description: "Print output from commands as they are run."
          switch "--force",
                 description: "Run with `--force`/`--overwrite`."
        end

        sig { override.void }
        def run
          require "bundle/commands/install"

          args_obj = T.unsafe(args)
          global_opt = args_obj.respond_to?(:global?) ? args_obj.global? : false
          file_opt = args_obj.respond_to?(:file) ? args_obj.file : nil
          verbose_opt = args_obj.respond_to?(:verbose?) ? args_obj.verbose? : false
          force_opt = args_obj.respond_to?(:force?) ? args_obj.force? : false
          quiet_opt = args_obj.respond_to?(:quiet?) ? args_obj.quiet? : false

          Homebrew::Bundle::Commands::Install.run(
            global:     global_opt,
            file:       file_opt,
            no_upgrade: false,
            verbose:    verbose_opt,
            force:      force_opt,
            quiet:      quiet_opt,
          )
        end
      end

      class DumpSubcommand < AbstractSubcommand
        cmd_args do
          flag "--file=",
               description: "Write to the `Brewfile` at this location."
          switch "--global",
                 description: "Write to the global Brewfile."
          switch "--force",
                 description: "Overwrite an existing `Brewfile`."
          switch "--describe",
                 description: "Add a description comment above each line."
          switch "--no-restart",
                 description: "Don't add `restart_service` to formula lines."
          switch "--formula", "--brews",
                 description: "Dump Homebrew formula dependencies."
          switch "--cask", "--casks",
                 description: "Dump Homebrew cask dependencies."
          switch "--tap", "--taps",
                 description: "Dump Homebrew tap dependencies."
          switch "--mas",
                 description: "Dump Mac App Store dependencies."
          switch "--whalebrew",
                 description: "Dump Whalebrew dependencies."
          switch "--vscode",
                 description: "Dump VSCode extensions."
          switch "--no-vscode",
                 description: "Don't dump VSCode extensions."
          conflicts "--vscode", "--no-vscode"
        end

        sig { override.void }
        def run
          require "bundle/commands/dump"

          args_obj = T.unsafe(args)
          no_vscode_opt = args_obj.respond_to?(:no_vscode?) ? args_obj.no_vscode? : false
          vscode_opt = args_obj.respond_to?(:vscode?) ? args_obj.vscode? : false
          brews_opt = args_obj.respond_to?(:brews?) ? args_obj.brews? : false
          casks_opt = args_obj.respond_to?(:casks?) ? args_obj.casks? : false
          taps_opt = args_obj.respond_to?(:taps?) ? args_obj.taps? : false
          mas_opt = args_obj.respond_to?(:mas?) ? args_obj.mas? : false
          whalebrew_opt = args_obj.respond_to?(:whalebrew?) ? args_obj.whalebrew? : false
          global_opt = args_obj.respond_to?(:global?) ? args_obj.global? : false
          file_opt = args_obj.respond_to?(:file) ? args_obj.file : nil
          force_opt = args_obj.respond_to?(:force?) ? args_obj.force? : false
          describe_opt = args_obj.respond_to?(:describe?) ? args_obj.describe? : false
          no_restart_opt = args_obj.respond_to?(:no_restart?) ? args_obj.no_restart? : false

          vscode = if no_vscode_opt
            false
          elsif vscode_opt
            true
          else
            !brews_opt && !casks_opt && !taps_opt && !mas_opt && !whalebrew_opt
          end

          default_all = !brews_opt && !casks_opt && !taps_opt && !mas_opt && !whalebrew_opt && !vscode_opt

          Homebrew::Bundle::Commands::Dump.run(
            global:     global_opt,
            file:       file_opt,
            force:      force_opt,
            describe:   describe_opt,
            no_restart: no_restart_opt,
            taps:       taps_opt || default_all,
            brews:      brews_opt || default_all,
            casks:      casks_opt || default_all,
            mas:        mas_opt || default_all,
            whalebrew:  whalebrew_opt || default_all,
            vscode:,
          )
        end
      end

      class CleanupSubcommand < AbstractSubcommand
        cmd_args do
          flag "--file=",
               description: "Read from the `Brewfile` from this location."
          switch "--global",
                 description: "Read from the global Brewfile."
          switch "--force",
                 description: "Actually perform the cleanup operations."
          switch "--zap",
                 description: "Use `zap` command instead of `uninstall` for casks."
        end

        sig { override.void }
        def run
          require "bundle/commands/cleanup"

          args_obj = T.unsafe(args)
          global_opt = args_obj.respond_to?(:global?) ? args_obj.global? : false
          file_opt = args_obj.respond_to?(:file) ? args_obj.file : nil
          force_opt = args_obj.respond_to?(:force?) ? args_obj.force? : false
          zap_opt = args_obj.respond_to?(:zap?) ? args_obj.zap? : false

          Homebrew::Bundle::Commands::Cleanup.run(
            global: global_opt,
            file:   file_opt,
            force:  force_opt,
            zap:    zap_opt,
          )
        end
      end

      class CheckSubcommand < AbstractSubcommand
        cmd_args do
          flag "--file=",
               description: "Read from the `Brewfile` from this location."
          switch "--global",
                 description: "Read from the global Brewfile."
          switch "--verbose",
                 description: "List all missing dependencies."
          switch "--no-upgrade",
                 description: "Don't check for outdated dependencies."
        end

        sig { override.void }
        def run
          require "bundle/commands/check"

          args_obj = T.unsafe(args)
          global_opt = args_obj.respond_to?(:global?) ? args_obj.global? : false
          file_opt = args_obj.respond_to?(:file) ? args_obj.file : nil
          no_upgrade_opt = args_obj.respond_to?(:no_upgrade?) ? args_obj.no_upgrade? : false
          verbose_opt = args_obj.respond_to?(:verbose?) ? args_obj.verbose? : false
          Homebrew::Bundle::Commands::Check.run(
            global:     global_opt,
            file:       file_opt,
            no_upgrade: no_upgrade_opt,
            verbose:    verbose_opt,
          )
        end
      end

      class ListSubcommand < AbstractSubcommand
        cmd_args do
          flag "--file=",
               description: "Read from the `Brewfile` from this location."
          switch "--global",
                 description: "Read from the global Brewfile."
          switch "--all",
                 description: "List all dependencies."
          switch "--formula", "--brews",
                 description: "List Homebrew formula dependencies."
          switch "--cask", "--casks",
                 description: "List Homebrew cask dependencies."
          switch "--tap", "--taps",
                 description: "List Homebrew tap dependencies."
          switch "--mas",
                 description: "List Mac App Store dependencies."
          switch "--whalebrew",
                 description: "List Whalebrew dependencies."
          switch "--vscode",
                 description: "List VSCode extensions."
        end

        sig { override.void }
        def run
          require "bundle/commands/list"

          args_obj = T.unsafe(args)
          global_opt = args_obj.respond_to?(:global?) ? args_obj.global? : false
          file_opt = args_obj.respond_to?(:file) ? args_obj.file : nil
          brews_opt = args_obj.respond_to?(:brews?) ? args_obj.brews? : false
          casks_opt = args_obj.respond_to?(:casks?) ? args_obj.casks? : false
          taps_opt = args_obj.respond_to?(:taps?) ? args_obj.taps? : false
          mas_opt = args_obj.respond_to?(:mas?) ? args_obj.mas? : false
          whalebrew_opt = args_obj.respond_to?(:whalebrew?) ? args_obj.whalebrew? : false
          vscode_opt = args_obj.respond_to?(:vscode?) ? args_obj.vscode? : false
          all_opt = args_obj.respond_to?(:all?) ? args_obj.all? : false

          default_formula = !brews_opt && !casks_opt && !taps_opt && !mas_opt && !whalebrew_opt && !vscode_opt

          Homebrew::Bundle::Commands::List.run(
            global:    global_opt,
            file:      file_opt,
            brews:     brews_opt || all_opt || default_formula,
            casks:     casks_opt || all_opt,
            taps:      taps_opt || all_opt,
            mas:       mas_opt || all_opt,
            whalebrew: whalebrew_opt || all_opt,
            vscode:    vscode_opt || all_opt,
          )
        end
      end

      class EditSubcommand < AbstractSubcommand
        cmd_args do
          flag "--file=",
               description: "Edit the `Brewfile` at this location."
          switch "--global",
                 description: "Edit the global Brewfile."
        end

        sig { override.void }
        def run
          require "bundle/brewfile"

          args_obj = T.unsafe(args)
          global_opt = args_obj.respond_to?(:global?) ? args_obj.global? : false
          file_opt = args_obj.respond_to?(:file) ? args_obj.file : nil

          exec_editor(Homebrew::Bundle::Brewfile.path(global: global_opt, file: file_opt))
        end
      end

      class ExecSubcommand < AbstractSubcommand
        cmd_args do
          flag "--file=",
               description: "Read from the `Brewfile` from this location."
          switch "--global",
                 description: "Read from the global Brewfile."
          switch "--install",
                 description: "Run `install` before continuing."
          switch "--services",
                 description: "Temporarily start services."
        end

        sig { override.void }
        def run
          require "bundle/commands/exec"

          subcommand = "exec"

          args_obj = T.unsafe(args)
          global_opt = args_obj.respond_to?(:global?) ? args_obj.global? : false
          file_opt = args_obj.respond_to?(:file) ? args_obj.file : nil
          install_opt = args_obj.respond_to?(:install?) ? args_obj.install? : false
          verbose_opt = args_obj.respond_to?(:verbose?) ? args_obj.verbose? : false
          force_opt = args_obj.respond_to?(:force?) ? args_obj.force? : false
          services_opt = args_obj.respond_to?(:services?) ? args_obj.services? : false
          named_args_array = args_obj.respond_to?(:named_args) ? args_obj.named_args : []

          if install_opt
            require "bundle/commands/install"
            redirect_stdout($stderr) do
              Homebrew::Bundle::Commands::Install.run(
                global:     global_opt,
                file:       file_opt,
                no_upgrade: true,
                verbose:    verbose_opt,
                force:      force_opt,
                quiet:      true,
              )
            end
          end

          Homebrew::Bundle::Commands::Exec.run(
            *named_args_array,
            global:     global_opt,
            file:       file_opt,
            subcommand: subcommand,
            services:   services_opt,
          )
        end
      end

      class ShSubcommand < AbstractSubcommand
        cmd_args do
          flag "--file=",
               description: "Read from the `Brewfile` from this location."
          switch "--global",
                 description: "Read from the global Brewfile."
          switch "--install",
                 description: "Run `install` before continuing."
          switch "--services",
                 description: "Temporarily start services."
        end

        sig { override.void }
        def run
          require "bundle/commands/exec"
          require "utils/shell"

          subcommand = "sh"
          preferred_path = Utils::Shell.preferred_path(default: "/bin/bash")
          notice = unless Homebrew::EnvConfig.no_env_hints?
            <<~EOS
              Your shell has been configured to use a build environment from your `Brewfile`.
              This should help you build stuff.
              Hide these hints with HOMEBREW_NO_ENV_HINTS (see `man brew`).
              When done, type `exit`.
            EOS
          end
          ENV["HOMEBREW_FORCE_API_AUTO_UPDATE"] = nil
          shell_cmd = Utils::Shell.shell_with_prompt("brew bundle", preferred_path: preferred_path, notice: notice)

          args_obj = T.unsafe(args)
          global_opt = args_obj.respond_to?(:global?) ? args_obj.global? : false
          file_opt = args_obj.respond_to?(:file) ? args_obj.file : nil
          install_opt = args_obj.respond_to?(:install?) ? args_obj.install? : false
          verbose_opt = args_obj.respond_to?(:verbose?) ? args_obj.verbose? : false
          force_opt = args_obj.respond_to?(:force?) ? args_obj.force? : false
          services_opt = args_obj.respond_to?(:services?) ? args_obj.services? : false

          if install_opt
            require "bundle/commands/install"
            redirect_stdout($stderr) do
              Homebrew::Bundle::Commands::Install.run(
                global:     global_opt,
                file:       file_opt,
                no_upgrade: true,
                verbose:    verbose_opt,
                force:      force_opt,
                quiet:      true,
              )
            end
          end

          Homebrew::Bundle::Commands::Exec.run(
            shell_cmd,
            global:     global_opt,
            file:       file_opt,
            subcommand: subcommand,
            services:   services_opt,
          )
        end
      end

      class EnvSubcommand < AbstractSubcommand
        cmd_args do
          flag "--file=",
               description: "Read from the `Brewfile` from this location."
          switch "--global",
                 description: "Read from the global Brewfile."
          switch "--install",
                 description: "Run `install` before continuing."
        end

        sig { override.void }
        def run
          require "bundle/commands/exec"

          args_obj = T.unsafe(args)
          global_opt = args_obj.respond_to?(:global?) ? args_obj.global? : false
          file_opt = args_obj.respond_to?(:file) ? args_obj.file : nil
          install_opt = args_obj.respond_to?(:install?) ? args_obj.install? : false
          verbose_opt = args_obj.respond_to?(:verbose?) ? args_obj.verbose? : false
          force_opt = args_obj.respond_to?(:force?) ? args_obj.force? : false

          if install_opt
            require "bundle/commands/install"
            redirect_stdout($stderr) do
              Homebrew::Bundle::Commands::Install.run(
                global:     global_opt,
                file:       file_opt,
                no_upgrade: true,
                verbose:    verbose_opt,
                force:      force_opt,
                quiet:      true,
              )
            end
          end

          Homebrew::Bundle::Commands::Exec.run(
            "env",
            global:     global_opt,
            file:       file_opt,
            subcommand: "env",
          )
        end
      end

      class AddSubcommand < AbstractSubcommand
        cmd_args do
          flag "--file=",
               description: "Add to the `Brewfile` at this location."
          switch "--global",
                 description: "Add to the global Brewfile."
          switch "--formula", "--brew",
                 description: "Add a Homebrew formula."
          switch "--cask",
                 description: "Add a Homebrew cask."
          switch "--tap",
                 description: "Add a Homebrew tap."
          switch "--whalebrew",
                 description: "Add a Whalebrew image."
          switch "--vscode",
                 description: "Add a VSCode extension."
        end

        sig { override.void }
        def run
          require "bundle/commands/add"

          args_obj = T.unsafe(args)
          formula_opt = args_obj.respond_to?(:formula?) ? args_obj.formula? : false
          brew_opt = args_obj.respond_to?(:brew?) ? args_obj.brew? : false
          cask_opt = args_obj.respond_to?(:cask?) ? args_obj.cask? : false
          tap_opt = args_obj.respond_to?(:tap?) ? args_obj.tap? : false
          whalebrew_opt = args_obj.respond_to?(:whalebrew?) ? args_obj.whalebrew? : false
          vscode_opt = args_obj.respond_to?(:vscode?) ? args_obj.vscode? : false
          global_opt = args_obj.respond_to?(:global?) ? args_obj.global? : false
          file_opt = args_obj.respond_to?(:file) ? args_obj.file : nil
          named_args_array = args_obj.respond_to?(:named_args) ? args_obj.named_args : []

          type_hash = {
            brew:      formula_opt || brew_opt,
            cask:      cask_opt,
            tap:       tap_opt,
            whalebrew: whalebrew_opt,
            vscode:    vscode_opt,
            none:      !formula_opt && !brew_opt && !cask_opt && !tap_opt && !whalebrew_opt && !vscode_opt,
          }
          selected_types = type_hash.select { |_, v| v }.keys
          raise UsageError, "`add` supports only one type of entry at a time." if selected_types.count != 1

          type = case (t = selected_types.first)
          when :none then :brew
          when :mas then raise UsageError, "`add` does not support `--mas`."
          else t
          end

          Homebrew::Bundle::Commands::Add.run(
            *named_args_array,
            type:   type,
            global: global_opt,
            file:   file_opt,
          )
        end
      end

      class RemoveSubcommand < AbstractSubcommand
        cmd_args do
          flag "--file=",
               description: "Remove from the `Brewfile` at this location."
          switch "--global",
                 description: "Remove from the global Brewfile."
          switch "--formula", "--brew",
                 description: "Remove a Homebrew formula."
          switch "--cask",
                 description: "Remove a Homebrew cask."
          switch "--tap",
                 description: "Remove a Homebrew tap."
          switch "--mas",
                 description: "Remove a Mac App Store dependency."
          switch "--whalebrew",
                 description: "Remove a Whalebrew image."
          switch "--vscode",
                 description: "Remove a VSCode extension."
        end

        sig { override.void }
        def run
          require "bundle/commands/remove"

          args_obj = T.unsafe(args)
          formula_opt = args_obj.respond_to?(:formula?) ? args_obj.formula? : false
          brew_opt = args_obj.respond_to?(:brew?) ? args_obj.brew? : false
          cask_opt = args_obj.respond_to?(:cask?) ? args_obj.cask? : false
          tap_opt = args_obj.respond_to?(:tap?) ? args_obj.tap? : false
          mas_opt = args_obj.respond_to?(:mas?) ? args_obj.mas? : false
          whalebrew_opt = args_obj.respond_to?(:whalebrew?) ? args_obj.whalebrew? : false
          vscode_opt = args_obj.respond_to?(:vscode?) ? args_obj.vscode? : false
          global_opt = args_obj.respond_to?(:global?) ? args_obj.global? : false
          file_opt = args_obj.respond_to?(:file) ? args_obj.file : nil
          named_args_array = args_obj.respond_to?(:named_args) ? args_obj.named_args : []

          type_hash = {
            brew:      formula_opt || brew_opt,
            cask:      cask_opt,
            tap:       tap_opt,
            mas:       mas_opt,
            whalebrew: whalebrew_opt,
            vscode:    vscode_opt,
            none:      !formula_opt && !brew_opt && !cask_opt && !tap_opt &&
                       !mas_opt && !whalebrew_opt && !vscode_opt,
          }
          selected_types = type_hash.select { |_, v| v }.keys
          raise UsageError, "`remove` supports only one type of entry at a time." if selected_types.count != 1

          Homebrew::Bundle::Commands::Remove.run(
            *named_args_array,
            type:   selected_types.first,
            global: global_opt,
            file:   file_opt,
          )
        end
      end
    end
  end
end
