# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula_installer"
require "development_tools"
require "install"
require "reinstall"
require "cask/utils"
require "cask/installer"
require "cask/reinstall"
require "upgrade"
require "api"
require "trust"

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
          reinstalled formulae and casks or, every 30 days, for all packages.
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
        switch "--no-ask", "--yes", "-y",
               description: "Do not ask for confirmation before downloading and reinstalling. " \
                            "Ask mode is the default.",
               env:         :no_ask
        switch "--ask",
               description: "Ask for confirmation before downloading and reinstalling. " \
                            "Print what would be reinstalled before prompting. Only prompts if the plan " \
                            "includes dependencies or dependants; if the requested formulae or casks are the " \
                            "only things to reinstall, it only prints the plan. The confirmation prompt is " \
                            "skipped without a TTY. This is the default unless `$HOMEBREW_NO_ASK` is set.",
               env:         :ask,
               replacement: "the default behaviour",
               odisabled:   true
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
                         "macOS, even if it would not normally be used for installation. " \
                         "Fail rather than build from source if a formula or dependency has no bottle.",
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
        conflicts "--ask", "--no-ask"

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
        Homebrew::Trust.trust_fully_qualified_items!(args.named, type: args.only_formula_or_cask)
        ask = !args.no_ask?

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

        if Homebrew::EnvConfig.verify_attestations?
          formulae = Homebrew::Attestation.sort_formulae_for_install(formulae)
        end
        casks = casks.filter_map do |cask|
          if cask.pinned?
            onoe "#{cask.full_name} is pinned. You must unpin it to reinstall."
            next
          end
          cask
        end
        shared_download_queue = T.let(nil, T.nilable(Homebrew::DownloadQueue))
        casks_prefetched = T.let(false, T::Boolean)
        reinstalled_formulae = T.let([], T::Array[Formula])
        prefetched_cask_installers = T.let([], T::Array[Cask::Installer])

        Install.ask_casks casks, action: "reinstallation", skip_cask_deps: args.skip_cask_deps? if ask

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

          formulae_installers = reinstall_contexts.map(&:formula_installer)
          if !ask && formulae_installers.any?
            download_queue = Homebrew::DownloadQueue.new(pour: true)
            shared_download_queue = download_queue
            formulae_installers = Install.prelude_fetch_formulae(formulae_installers, download_queue:)
          end

          dependants = begin
            Upgrade.dependants(
              formulae,
              flags:                      args.flags_only,
              ask:                        ask,
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
          # Ensure the early download queue is shut down on interrupts.
          rescue Exception # rubocop:disable Lint/RescueException
            shared_download_queue&.shutdown
            raise
          end

          # Main block: if asking the user is enabled, show dry-run information.
          if ask
            Install.ask_formulae(
              formulae_installers,
              dependants,
              action:                     "reinstallation",
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
            )
          end

          dependent_formulae_installers = Upgrade.dependent_formula_installers(
            dependants,
            formulae,
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
          )

          shared_download_queue ||= Homebrew::DownloadQueue.new(pour: true)
          download_queue = shared_download_queue
          begin
            all_formulae_installers = Install.enqueue_formulae(
              (formulae_installers + dependent_formulae_installers).uniq { |fi| fi.formula.full_name },
              download_queue:,
            )
            formulae_installers &= all_formulae_installers
            dependent_formulae_installers &= all_formulae_installers

            if casks.any?
              prefetched_cask_installers = casks.map do |cask|
                Cask::Installer.new(
                  cask,
                  binaries:       args.binaries?,
                  verbose:        args.verbose?,
                  force:          args.force?,
                  skip_cask_deps: args.skip_cask_deps?,
                  require_sha:    args.require_sha?,
                  reinstall:      true,
                  zap:            args.zap?,
                  download_queue:,
                  defer_fetch:    true,
                )
              end
              prefetched_cask_installers = Install.enqueue_cask_installers(prefetched_cask_installers)
            end

            download_queue.fetch(heading: Install.combined_fetch_downloads_heading(
              formula_names: all_formulae_installers.map { |fi| fi.formula.name },
              cask_names:    casks.map(&:full_name),
            ))
            Install.fetch_cask_dependencies(prefetched_cask_installers, download_queue:)
            casks_prefetched = casks.any?
            all_formulae_installers = Install.reject_failed_downloads(all_formulae_installers, download_queue:)
            formulae_installers &= all_formulae_installers
            dependent_formulae_installers &= all_formulae_installers
          ensure
            download_queue.shutdown
          end

          # Reinstall everything that did download, rather than aborting the
          # whole run; the failures above still exit nonzero at the end.
          reinstall_contexts.each do |reinstall_context|
            next unless formulae_installers.include?(reinstall_context.formula_installer)

            Homebrew::Reinstall.reinstall_formula(reinstall_context)
            reinstalled_formulae << reinstall_context.formula
          rescue BuildError
            # Reported (with analytics) by the global handler in `brew.rb`.
            raise
          rescue => e
            ofail "#{reinstall_context.formula.full_specified_name}: #{e}"
          end

          reinstalled_formulae |= Upgrade.upgrade_dependents(
            dependants, formulae,
            flags:                         args.flags_only,
            force_bottle:                  args.force_bottle?,
            build_from_source_formulae:    args.build_from_source_formulae,
            interactive:                   args.interactive?,
            keep_tmp:                      args.keep_tmp?,
            debug_symbols:                 args.debug_symbols?,
            force:                         args.force?,
            debug:                         args.debug?,
            quiet:                         args.quiet?,
            verbose:                       args.verbose?,
            cleanup:                       false,
            prefetched_formula_installers: dependent_formulae_installers
          )
        end

        reinstalled_casks = T.let([], T::Array[Cask::Cask])
        if casks.any?
          begin
            reinstalled_casks = Cask::Reinstall.reinstall_casks(
              *casks,
              binaries:        args.binaries?,
              verbose:         args.verbose?,
              force:           args.force?,
              require_sha:     args.require_sha?,
              skip_cask_deps:  args.skip_cask_deps?,
              zap:             args.zap?,
              skip_prefetch:   casks_prefetched,
              download_queue:  nil,
              cask_installers: prefetched_cask_installers.presence,
            )
          rescue => e
            ofail e
          end
        end

        unavailable_errors.each { |e| ofail e }

        Install.finish_installation(
          formulae:      reinstalled_formulae,
          casks:         reinstalled_casks,
          display_times: args.display_times?,
        )
      end
    end
  end
end
