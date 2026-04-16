# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula_installer"
require "development_tools"
require "messages"
require "install"
require "reinstall"
require "cleanup"
require "cask/utils"
require "cask/reinstall"
require "upgrade"
require "api"

module Homebrew
  module Cmd
    class Reinstall < AbstractCommand
      cmd_args do
        description <<~EOS
          Uninstall and then reinstall a <formula> or <cask> using the same options it was
          originally installed with, plus any appended options specific to a <formula>.

          Unless `$HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK` is set, `brew upgrade` or `brew reinstall` will be run for
          outdated dependents and dependents with broken linkage, respectively.

          Unless `$HOMEBREW_NO_INSTALL_CLEANUP` is set, `brew cleanup` will then be run for the
          reinstalled formulae or, every 30 days, for all formulae.
        EOS
        switch "-d", "--debug",
               description: "If brewing fails, open an interactive debugging session with access to IRB " \
                            "or a shell inside the temporary build directory."
        switch "--display-times",
               description: "Print install times for each package at the end of the run.",
               env:         :display_install_times
        switch "-f", "--force",
               description: "Install without checking for previously installed keg-only or " \
                            "non-migrated versions."
        switch "-v", "--verbose",
               description: "Print the verification and post-install steps."
        switch "--ask",
               description: "Ask for confirmation before downloading and upgrading formulae. " \
                            "Print download, install and net install sizes of bottles and dependencies.",
               env:         :ask
        [
          [:switch, "--formula", "--formulae", {
            description: "Treat all named arguments as formulae.",
          }],
          [:switch, "-s", "--build-from-source", {
            description: "Compile <formula> from source even if a bottle is available.",
          }],
          [:switch, "-i", "--interactive", {
            description: "Download and patch <formula>, then open a shell. This allows the user to " \
                         "run `./configure --help` and otherwise determine how to turn the software " \
                         "package into a Homebrew package.",
          }],
          [:switch, "--force-bottle", {
            description: "Install from a bottle if it exists for the current or newest version of " \
                         "macOS, even if it would not normally be used for installation.",
          }],
          [:switch, "--keep-tmp", {
            description: "Retain the temporary files created during installation.",
          }],
          [:switch, "--debug-symbols", {
            depends_on:  "--build-from-source",
            description: "Generate debug symbols on build. Source will be retained in a cache directory.",
          }],
          [:switch, "-g", "--git", {
            description: "Create a Git repository, useful for creating patches to the software.",
          }],
        ].each do |args|
          options = args.pop
          send(*args, **options)
          conflicts "--cask", args.last
        end
        formula_options
        [
          [:switch, "--cask", "--casks", {
            description: "Treat all named arguments as casks.",
          }],
          [:switch, "--[no-]binaries", {
            description: "Disable/enable linking of helper executables (default: enabled).",
            env:         :cask_opts_binaries,
          }],
          [:switch, "--require-sha", {
            description: "Require all casks to have a checksum.",
            env:         :cask_opts_require_sha,
          }],
          [:switch, "--[no-]quarantine", {
            env:       :cask_opts_quarantine,
            odisabled: true,
          }],
          [:switch, "--adopt", {
            description: "Adopt existing artifacts in the destination that are identical to those being installed. " \
                         "Cannot be combined with `--force`.",
          }],
          [:switch, "--skip-cask-deps", {
            description: "Skip installing cask dependencies.",
          }],
          [:switch, "--zap", {
            description: "For use with `brew reinstall --cask`. Remove all files associated with a cask. " \
                         "*May remove files which are shared between applications.*",
          }],
        ].each do |args|
          options = args.pop
          send(*args, **options)
          conflicts "--formula", args.last
        end
        cask_options

        conflicts "--build-from-source", "--force-bottle"

        named_args [:formula, :cask], min: 1
      end

      sig { override.void }
      def run
        formulae = T.let([], T::Array[Formula])
        casks = T.let([], T::Array[Cask::Cask])
        unavailable_errors = T.let(
          [],
          T::Array[T.any(FormulaOrCaskUnavailableError, NoSuchKegError)],
        )

        args.named.to_formulae_and_casks_and_unavailable(method: :resolve).each do |item|
          case item
          when FormulaOrCaskUnavailableError, NoSuchKegError
            unavailable_errors << item
          when Formula
            formulae << item
          when Cask::Cask
            casks << item
          end
        end

        if args.build_from_source?
          unless DevelopmentTools.installed?
            raise BuildFlagsError.new(["--build-from-source"], bottled: formulae.all?(&:bottled?))
          end

          unless Homebrew::EnvConfig.developer?
            opoo "building from source is not supported!"
            puts "You're on your own. Failures are expected so don't create any issues, please!"
          end
        end

        formulae = Homebrew::Attestation.sort_formulae_for_install(formulae) if Homebrew::Attestation.enabled?
        shared_download_queue = T.let(nil, T.nilable(Homebrew::DownloadQueue))
        casks_prefetched = T.let(false, T::Boolean)

        unless formulae.empty?
          Install.perform_preinstall_checks_once

          reinstall_contexts = formulae.filter_map do |formula|
            if formula.pinned?
              onoe "#{formula.full_name} is pinned. You must unpin it to reinstall."
              next
            end
            Migrator.migrate_if_needed(formula, force: args.force?)
            Homebrew::Reinstall.build_install_context(
              formula.latest_formula,
              flags:                      args.flags_only,
              force_bottle:               args.force_bottle?,
              build_from_source_formulae: args.build_from_source_formulae,
              interactive:                args.interactive?,
              keep_tmp:                   args.keep_tmp?,
              debug_symbols:              args.debug_symbols?,
              force:                      args.force?,
              debug:                      args.debug?,
              quiet:                      args.quiet?,
              verbose:                    args.verbose?,
              git:                        args.git?,
            )
          end

          dependants = Upgrade.dependants(
            formulae,
            flags:                      args.flags_only,
            ask:                        args.ask?,
            force_bottle:               args.force_bottle?,
            build_from_source_formulae: args.build_from_source_formulae,
            interactive:                args.interactive?,
            keep_tmp:                   args.keep_tmp?,
            debug_symbols:              args.debug_symbols?,
            force:                      args.force?,
            debug:                      args.debug?,
            quiet:                      args.quiet?,
            verbose:                    args.verbose?,
          )

          formulae_installers = reinstall_contexts.map(&:formula_installer)

          # Main block: if asking the user is enabled, show dependency and size information.
          Install.ask_formulae(formulae_installers, dependants, args: args) if args.ask?

          valid_formula_installers = if casks.any?
            shared_download_queue = Homebrew::DownloadQueue.new(pour: true)
            begin
              Install.show_combined_fetch_downloads_heading(
                formula_names: formulae_installers.map { |fi| fi.formula.name },
                cask_names:    casks.map(&:full_name),
              )

              valid_formula_installers = Install.enqueue_formulae(formulae_installers,
                                                                  download_queue: shared_download_queue)

              require "cask/installer"
              fetch_cask_installers = casks.map do |cask|
                Cask::Installer.new(
                  cask,
                  binaries:       args.binaries?,
                  verbose:        args.verbose?,
                  force:          args.force?,
                  skip_cask_deps: args.skip_cask_deps?,
                  require_sha:    args.require_sha?,
                  reinstall:      true,
                  quarantine:     args.quarantine?,
                  zap:            args.zap?,
                  download_queue: shared_download_queue,
                  defer_fetch:    true,
                )
              end
              Install.enqueue_cask_installers(fetch_cask_installers)
              shared_download_queue.fetch
              casks_prefetched = true
              valid_formula_installers
            ensure
              shared_download_queue.shutdown
            end
          else
            Install.fetch_formulae(formulae_installers)
          end

          exit 1 if Homebrew.failed?

          reinstall_contexts.each do |reinstall_context|
            next unless valid_formula_installers.include?(reinstall_context.formula_installer)

            Homebrew::Reinstall.reinstall_formula(reinstall_context)
            Cleanup.install_formula_clean!(reinstall_context.formula)
          end

          Upgrade.upgrade_dependents(
            dependants, formulae,
            flags:                      args.flags_only,
            force_bottle:               args.force_bottle?,
            build_from_source_formulae: args.build_from_source_formulae,
            interactive:                args.interactive?,
            keep_tmp:                   args.keep_tmp?,
            debug_symbols:              args.debug_symbols?,
            force:                      args.force?,
            debug:                      args.debug?,
            quiet:                      args.quiet?,
            verbose:                    args.verbose?
          )
        end

        if casks.any?
          Install.ask_casks casks if args.ask?
          begin
            Cask::Reinstall.reinstall_casks(
              *casks,
              binaries:       args.binaries?,
              verbose:        args.verbose?,
              force:          args.force?,
              require_sha:    args.require_sha?,
              skip_cask_deps: args.skip_cask_deps?,
              quarantine:     args.quarantine?,
              zap:            args.zap?,
              skip_prefetch:  casks_prefetched,
              download_queue: nil,
            )
          rescue => e
            ofail e
          end
        end

        unavailable_errors.each { |e| ofail e }

        Cleanup.periodic_clean!

        Homebrew.messages.display_messages(display_times: args.display_times?)
      end
    end
  end
end
