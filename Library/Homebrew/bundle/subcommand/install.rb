# typed: strict
# frozen_string_literal: true

require "abstract_subcommand"

require "bundle/brewfile"
require "bundle/installer"
module Homebrew
  module Cmd
    class Bundle < Homebrew::AbstractCommand
      class InstallSubcommand < Homebrew::AbstractSubcommand
        subcommand_args alias_options: { "upgrade" => "--upgrade" }, default: true do
          usage_banner <<~EOS
            `brew bundle` [`install`|`upgrade`]:
            Install and upgrade (by default) all dependencies from the `Brewfile`.

            Use this to restore a recorded installed state from a `Brewfile`.

            `brew bundle upgrade` is shorthand for `brew bundle install --upgrade`.

            You can specify the `Brewfile` location using `--file` or by setting the `$HOMEBREW_BUNDLE_FILE` environment variable.

            You can skip the installation of dependencies by adding space-separated values to one or more of the following environment variables: `$HOMEBREW_BUNDLE_BREW_SKIP`, `$HOMEBREW_BUNDLE_CASK_SKIP`, `$HOMEBREW_BUNDLE_MAS_SKIP`, `$HOMEBREW_BUNDLE_TAP_SKIP`.
          EOS
          named_args :none
          switch "-v", "--verbose",
                 description: "Print output from commands as they are run."
          switch "--no-upgrade",
                 description: "Do not run `brew upgrade` on outdated dependencies. " \
                              "Note they may still be upgraded by `brew install` if needed.",
                 env:         :bundle_no_upgrade
          switch "--upgrade",
                 description: "Run `brew upgrade` on outdated dependencies, " \
                              "even if `$HOMEBREW_BUNDLE_NO_UPGRADE` is set."
          flag   "--upgrade-formulae=", "--upgrade-formula=",
                 description: "Run `brew upgrade` on any of these comma-separated formulae, " \
                              "even if `$HOMEBREW_BUNDLE_NO_UPGRADE` is set."
          # odeprecated: change default for 5.2 and document HOMEBREW_BUNDLE_JOBS
          flag "--jobs=",
               description: "Run up to this many formula installations in parallel. " \
                            "Defaults to 1 (sequential). Use `auto` for the number of CPU cores (max 4)."
          switch "-f", "--force",
                 description: "Run with `--force`/`--overwrite`."
          switch "--cleanup",
                 description: "Ask to perform cleanup after installing dependencies. Requires `--force`, " \
                              "`--force-cleanup` or `$HOMEBREW_ASK`.",
                 env:         [:bundle_install_cleanup, "--global"],
                 odeprecated: true
          switch "--force-cleanup",
                 description: "Perform cleanup after installing dependencies without asking.",
                 env:         [:bundle_force_install_cleanup, "--global"]
          switch "--zap",
                 description: "Use `zap` instead of `uninstall` when cleaning up casks after " \
                              "installing dependencies."
        end

        sig { override.void }
        def run
          if args.zap? && !args.cleanup? && !args.force_cleanup?
            raise UsageError, "`--zap` cannot be passed without `--cleanup` or `--force-cleanup`."
          end

          if args.cleanup? && !context.force && !args.force_cleanup? && !context.ask
            raise UsageError, "`brew bundle install --cleanup` requires `--force`, `--force-cleanup` " \
                              "or `$HOMEBREW_ASK`."
          end

          @dsl = Homebrew::Bundle::Brewfile.read(global: context.global, file: context.file)
          result = Homebrew::Bundle::Installer.install!(
            @dsl.entries,
            global:     context.global,
            file:       context.file,
            no_lock:    false,
            no_upgrade: context.no_upgrade,
            verbose:    context.verbose,
            force:      context.force,
            jobs:       context.jobs,
            quiet:      quiet || args.quiet?,
          )

          # Mark Brewfile formulae as installed_on_request to prevent autoremove
          # from removing them when their dependents are uninstalled
          Homebrew::Bundle.mark_as_installed_on_request!(@dsl.entries)

          result || exit(1)

          return unless cleanup

          cleanup_requested = args.force_cleanup? || args.cleanup?
          return unless cleanup_requested

          require "bundle/subcommand/cleanup"

          # Don't need to reset cleanup specifically but this resets all the dumper modules.
          Homebrew::Cmd::Bundle::CleanupSubcommand.reset!
          Homebrew::Cmd::Bundle::CleanupSubcommand.cleanup(
            global: context.global, file: context.file, zap: context.zap,
            force: context.force || args.force_cleanup?,
            ask: context.ask, dsl:
          )
        end

        sig { returns(T.nilable(Homebrew::Bundle::Dsl)) }
        def dsl
          @dsl ||= T.let(nil, T.nilable(Homebrew::Bundle::Dsl))
          @dsl
        end
      end
    end
  end
end
