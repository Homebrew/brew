# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "bundle/dsl"
require "bundle/extensions"

module Homebrew
  module Cmd
    class Bundle < AbstractCommand
      sig { params(args: Args, extension: T.class_of(Homebrew::Bundle::Extension)).returns(T::Boolean) }
      def self.extension_selected?(args, extension)
        args.public_send(extension.predicate_method)
      end

      sig { params(args: Args, extension: T.class_of(Homebrew::Bundle::Extension)).returns(T::Boolean) }
      def self.extension_dump_disabled?(args, extension)
        args.public_send(extension.dump_disable_predicate_method)
      end

      BUNDLE_EXTENSIONS = T.let(Homebrew::Bundle.extensions.dup.freeze, T::Array[T.class_of(Homebrew::Bundle::Extension)])
      BUNDLE_SOURCES_DESCRIPTION = T.let(
        [
          "Homebrew",
          "Homebrew Cask",
          *BUNDLE_EXTENSIONS.map(&:banner_name),
        ].to_sentence.freeze,
        String,
      )
      BUNDLE_ADD_FLAGS_DESCRIPTION = T.let(
        ["`--cask`", "`--tap`", *BUNDLE_EXTENSIONS.select(&:add_supported?).map do |extension|
          "`--#{extension.flag}`"
        end].to_sentence.freeze,
        String,
      )
      BUNDLE_REMOVE_FLAGS_DESCRIPTION = T.let(
        ["`--formula`", "`--cask`", "`--tap`", *BUNDLE_EXTENSIONS.select(&:remove_supported?).map do |extension|
          "`--#{extension.flag}`"
        end].to_sentence.freeze,
        String,
      )

      cmd_args do
        usage_banner <<~EOS
          `bundle` [<subcommand>]

          Bundler for non-Ruby dependencies from #{BUNDLE_SOURCES_DESCRIPTION}.

          Note: Flatpak support is only available on Linux.

          `brew bundle` [`install`]:
          Install and upgrade (by default) all dependencies from the `Brewfile`.

          You can specify the `Brewfile` location using `--file` or by setting the `$HOMEBREW_BUNDLE_FILE` environment variable.

          You can skip the installation of dependencies by adding space-separated values to one or more of the following environment variables: `$HOMEBREW_BUNDLE_BREW_SKIP`, `$HOMEBREW_BUNDLE_CASK_SKIP`, `$HOMEBREW_BUNDLE_MAS_SKIP`, `$HOMEBREW_BUNDLE_TAP_SKIP`.

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
          Add entries to your `Brewfile`. Adds formulae by default. Use #{BUNDLE_ADD_FLAGS_DESCRIPTION} to add the corresponding entry instead.

          `brew bundle remove` <name> [...]:
          Remove entries that match `name` from your `Brewfile`. Use #{BUNDLE_REMOVE_FLAGS_DESCRIPTION} to remove only entries of the corresponding type. Passing `--formula` also removes matches against formula aliases and old formula names.

          `brew bundle exec` [`--check`] [`--no-secrets`] <command>:
          Run an external command in an isolated build environment based on the `Brewfile` dependencies.

          This sanitized build environment ignores unrequested dependencies, which makes sure that things you didn't specify in your `Brewfile` won't get picked up by commands like `bundle install`, `npm install`, etc. It will also add compiler flags which will help with finding keg-only dependencies like `openssl`, `icu4c`, etc.

          `brew bundle sh` [`--check`] [`--no-secrets`]:
          Run your shell in a `brew bundle exec` environment.

          `brew bundle env` [`--check`] [`--no-secrets`]:
          Print the environment variables that would be set in a `brew bundle exec` environment.
        EOS
        flag   "--file=",
               description: "Read from or write to the `Brewfile` from this location. " \
                            "Use `--file=-` to pipe to stdin/stdout."
        switch "-g", "--global",
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
        flag   "--upgrade-formulae=", "--upgrade-formula=",
               description: "`install` runs `brew upgrade` on any of these comma-separated formulae, " \
                            "even if `$HOMEBREW_BUNDLE_NO_UPGRADE` is set."
        switch "--install",
               description: "Run `install` before continuing to other operations, e.g. `exec`."
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
        switch "--formula", "--formulae", "--brews",
               description: "`list`, `dump` or `cleanup` Homebrew formula dependencies."
        switch "--cask", "--casks",
               description: "`list`, `dump` or `cleanup` Homebrew cask dependencies."
        switch "--tap", "--taps",
               description: "`list`, `dump` or `cleanup` Homebrew tap dependencies."
        BUNDLE_EXTENSIONS.each do |extension|
          switch "--#{extension.flag}",
                 description: extension.switch_description
        end
        BUNDLE_EXTENSIONS.select(&:dump_disable_supported?).each do |extension|
          switch "--no-#{extension.flag}",
                 description: extension.dump_disable_description,
                 env:         extension.dump_disable_env
        end
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
                            "running `exec`, `sh`, or `env`.",
               env:         :bundle_check
        switch "--no-secrets",
               description: "Attempt to remove secrets from the environment before `exec`, `sh`, or `env`.",
               env:         :bundle_no_secrets

        BUNDLE_EXTENSIONS.select(&:dump_disable_supported?).each do |extension|
          conflicts "--all", "--no-#{extension.flag}"
          conflicts "--#{extension.flag}", "--no-#{extension.flag}"
        end
        conflicts "--install", "--upgrade"
        conflicts "--file", "--global"

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

        if args.check? && !ENV["HOMEBREW_BUNDLE_CHECK"] && BUNDLE_EXEC_COMMANDS.exclude?(subcommand)
          raise UsageError, "`--check` can be used only with #{BUNDLE_EXEC_COMMANDS.join(", ")}."
        end

        if args.no_secrets? && !ENV["HOMEBREW_BUNDLE_NO_SECRETS"] && BUNDLE_EXEC_COMMANDS.exclude?(subcommand)
          raise UsageError, "`--no-secrets` can be used only with #{BUNDLE_EXEC_COMMANDS.join(", ")}."
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

        no_type_args = ([args.formulae?, args.casks?, args.taps?] +
                        BUNDLE_EXTENSIONS.map { |extension| self.class.extension_selected?(args, extension) }).none?

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
            # Don't need to reset cleanup specifically but this resets all the dumper modules.
            Homebrew::Bundle::Commands::Cleanup.reset!
            Homebrew::Bundle::Commands::Cleanup.run(
              global:, file:, zap:,
              force:  true,
              dsl:    Homebrew::Bundle::Commands::Install.dsl
            )
          end
        when "dump"
          require "bundle/commands/dump"
          Homebrew::Bundle::Commands::Dump.run(
            global:, file:, force:,
            describe:   args.describe?,
            no_restart: args.no_restart?,
            taps:       args.taps? || no_type_args,
            formulae:   args.formulae? || no_type_args,
            casks:      args.casks? || no_type_args,
            extension_types: BUNDLE_EXTENSIONS.select(&:dump_supported?).to_h do |extension|
              disabled = extension.dump_disable_supported? && self.class.extension_dump_disabled?(args, extension)
              enabled = !disabled && (self.class.extension_selected?(args, extension) || no_type_args)
              [extension.type, enabled]
            end
          )
        when "edit"
          require "bundle/brewfile"
          exec_editor(Homebrew::Bundle::Brewfile.path(global:, file:))
        when "cleanup"
          require "bundle/commands/cleanup"
          Homebrew::Bundle::Commands::Cleanup.run(
            global:, file:, force:, zap:,
            formulae:        args.formulae? || no_type_args,
            casks:           args.casks? || no_type_args,
            taps:            args.taps? || no_type_args,
            extension_types: BUNDLE_EXTENSIONS.select(&:cleanup_supported?).to_h do |extension|
              [extension.type, self.class.extension_selected?(args, extension) || no_type_args]
            end
          )
        when "check"
          require "bundle/commands/check"
          Homebrew::Bundle::Commands::Check.run(global:, file:, no_upgrade:, verbose:)
        when "list"
          extension_list_options = BUNDLE_EXTENSIONS.to_h do |extension|
            [extension.type, self.class.extension_selected?(args, extension) || args.all?]
          end

          require "bundle/commands/list"
          Homebrew::Bundle::Commands::List.run(
            global:,
            file:,
            formulae:        args.formulae? || args.all? || no_type_args,
            casks:           args.casks? || args.all?,
            taps:            args.taps? || args.all?,
            extension_types: extension_list_options,
          )
        when "add", "remove"
          # We intentionally omit the s from `brews`, `casks`, and `taps` for ease of handling later.
          type_hash = {
            brew: args.formulae?,
            cask: args.casks?,
            tap:  args.taps?,
          }
          BUNDLE_EXTENSIONS.each do |extension|
            type_hash[extension.type] = self.class.extension_selected?(args, extension)
          end
          type_hash[:none] = no_type_args
          selected_types = type_hash.select { |_, v| v }.keys
          raise UsageError, "`#{subcommand}` supports only one type of entry at a time." if selected_types.count != 1

          _, *named_args = args.named
          if subcommand == "add"
            type = case (t = selected_types.first)
            when :none then :brew
            when :mas then raise UsageError, "`add` does not support `--mas`."
            else t
            end

            extension = Homebrew::Bundle.extension(type)
            if extension && !extension.add_supported?
              raise UsageError,
                    "`add` does not support `--#{extension.flag}`."
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
          Homebrew::Bundle::Commands::Exec.run(
            *named_args,
            global:,
            file:,
            subcommand:,
            services:   args.services?,
            no_secrets: args.no_secrets?,
          )
        else
          raise UsageError, "unknown subcommand: #{subcommand}"
        end
      end
    end
  end
end
