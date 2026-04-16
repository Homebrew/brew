# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula_installer"
require "install"
require "upgrade"
require "cask/utils"
require "cask/upgrade"
require "api"
require "reinstall"

module Homebrew
  module Cmd
    class UpgradeCmd < AbstractCommand
      class FormulaeUpgradeContext < T::Struct
        const :formulae_to_install, T::Array[Formula]
        const :formulae_installer, T::Array[FormulaInstaller]
        const :dependants, Homebrew::Upgrade::Dependents
      end

      cmd_args do
        description <<~EOS
          Upgrade outdated casks and outdated, unpinned formulae using the same options they were originally
          installed with, plus any appended brew formula options. If <cask> or <formula> are specified,
          upgrade only the given <cask> or <formula> kegs (unless they are pinned; see `pin`, `unpin`).

          Unless `$HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK` is set, `brew upgrade` or `brew reinstall` will be run for
          outdated dependents and dependents with broken linkage, respectively.

          Unless `$HOMEBREW_NO_INSTALL_CLEANUP` is set, `brew cleanup` will then be run for the
          upgraded formulae or, every 30 days, for all formulae.
        EOS
        switch "-d", "--debug",
               description: "If brewing fails, open an interactive debugging session with access to IRB " \
                            "or a shell inside the temporary build directory."
        switch "--display-times",
               description: "Print install times for each package at the end of the run.",
               env:         :display_install_times
        switch "-f", "--force",
               description: "Install formulae without checking for previously installed keg-only or " \
                            "non-migrated versions. When installing casks, overwrite existing files " \
                            "(binaries and symlinks are excluded, unless originally from the same cask)."
        switch "-v", "--verbose",
               description: "Print the verification and post-install steps."
        switch "-n", "--dry-run",
               description: "Show what would be upgraded, but do not actually upgrade anything."
        switch "--ask",
               description: "Ask for confirmation before downloading and upgrading formulae. " \
                            "Print download, install and net install sizes of bottles and dependencies.",
               env:         :ask
        [
          [:switch, "--formula", "--formulae", {
            description: "Treat all named arguments as formulae. If no named arguments " \
                         "are specified, upgrade only outdated formulae.",
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
          [:switch, "--fetch-HEAD", {
            description: "Fetch the upstream repository to detect if the HEAD installation of the " \
                         "formula is outdated. Otherwise, the repository's HEAD will only be checked for " \
                         "updates when a new stable or development version has been released.",
          }],
          [:switch, "--keep-tmp", {
            description: "Retain the temporary files created during installation.",
          }],
          [:switch, "--debug-symbols", {
            depends_on:  "--build-from-source",
            description: "Generate debug symbols on build. Source will be retained in a cache directory.",
          }],
          [:switch, "--overwrite", {
            description: "Delete files that already exist in the prefix while linking.",
          }],
        ].each do |args|
          options = args.pop
          send(*args, **options)
          conflicts "--cask", args.last
        end
        formula_options
        [
          [:switch, "--cask", "--casks", {
            description: "Treat all named arguments as casks. If no named arguments " \
                         "are specified, upgrade only outdated casks.",
          }],
          [:switch, "--skip-cask-deps", {
            description: "Skip installing cask dependencies.",
          }],
          [:switch, "-g", "--greedy", {
            description: "Also include casks with `version :latest` and `auto_updates true` casks " \
                         "that would otherwise be skipped.",
            env:         :upgrade_greedy,
          }],
          [:switch, "--greedy-latest", {
            description: "Also include casks with `version :latest`.",
          }],
          [:switch, "--greedy-auto-updates", {
            description: "Also include `auto_updates true` casks that would otherwise be skipped.",
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
        ].each do |args|
          options = args.pop
          send(*args, **options)
          conflicts "--formula", args.last
        end
        cask_options

        conflicts "--build-from-source", "--force-bottle"

        named_args [:installed_formula, :installed_cask]
      end

      sig { override.void }
      def run
        if args.build_from_source? && args.named.empty?
          raise ArgumentError, "`--build-from-source` requires at least one formula"
        end

        formulae = T.let([], T::Array[Formula])
        casks = T.let([], T::Array[Cask::Cask])
        unavailable_errors = T.let(
          [],
          T::Array[T.any(FormulaOrCaskUnavailableError, NoSuchKegError)],
        )
        @prefetched_formulae_upgrade_context = T.let(nil, T.nilable(FormulaeUpgradeContext))
        prefetched_formulae_names = T.let([], T::Array[String])
        prefetched_formulae_upgrades = T.let([], T::Array[String])
        prefetched_cask_names = T.let([], T::Array[String])
        prefetched_cask_upgrades = T.let([], T::Array[String])

        if args.named.present?
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
        end

        # If one or more formulae are specified, but no casks were
        # specified, we want to make note of that so we don't
        # try to upgrade all outdated casks.
        #
        # When names were given, we must also prevent empty resolved lists
        # from triggering the "upgrade all" path (which happens when all
        # names failed resolution).
        named_given = args.named.present?
        only_upgrade_formulae = (named_given && casks.blank?) || (formulae.present? && casks.blank?)
        only_upgrade_casks = (named_given && formulae.blank?) || (casks.present? && formulae.blank?)

        formulae = Homebrew::Attestation.sort_formulae_for_install(formulae) if Homebrew::Attestation.enabled?

        prefetched_casks = T.let(false, T::Boolean)
        shared_download_queue = T.let(nil, T.nilable(Homebrew::DownloadQueue))
        if !args.dry_run? && !only_upgrade_formulae && !only_upgrade_casks
          shared_download_queue = Homebrew::DownloadQueue.new(pour: true)
          begin
            upgrade_outdated_formulae!(
              formulae,
              prefetch_only:          true,
              download_queue:         shared_download_queue,
              prefetch_names:         prefetched_formulae_names,
              prefetch_upgrades:      prefetched_formulae_upgrades,
              show_upgrade_summary:   false,
              show_downloads_heading: false,
            )
            prefetched_casks = prefetch_outdated_casks!(
              casks,
              download_queue:         shared_download_queue,
              prefetch_names:         prefetched_cask_names,
              prefetch_upgrades:      prefetched_cask_upgrades,
              show_downloads_heading: false,
            )
            Cask::Upgrade.show_upgrade_summary(
              prefetched_formulae_upgrades + prefetched_cask_upgrades,
              dry_run: args.dry_run?,
            )
            Install.show_combined_fetch_downloads_heading(
              formula_names: prefetched_formulae_names,
              cask_names:    prefetched_cask_names,
            )
            shared_download_queue.fetch
          ensure
            shared_download_queue.shutdown
          end
        end

        upgrade_outdated_formulae!(formulae, use_prefetched: true) unless only_upgrade_casks
        unless only_upgrade_formulae
          upgrade_outdated_casks!(
            casks,
            skip_prefetch:  prefetched_casks,
            download_queue: nil,
          )
        end

        unavailable_errors.each { |e| ofail e }

        Cleanup.periodic_clean!(dry_run: args.dry_run?)

        Homebrew::Reinstall.reinstall_pkgconf_if_needed!(dry_run: args.dry_run?)

        Homebrew.messages.display_messages(display_times: args.display_times?)
      end

      private

      sig { params(formulae: T::Array[Formula], show_upgrade_summary: T::Boolean).returns(T.nilable(FormulaeUpgradeContext)) }
      def formulae_upgrade_context(formulae, show_upgrade_summary: true)
        if args.build_from_source?
          unless DevelopmentTools.installed?
            raise BuildFlagsError.new(["--build-from-source"], bottled: formulae.all?(&:bottled?))
          end

          unless Homebrew::EnvConfig.developer?
            opoo "building from source is not supported!"
            puts "You're on your own. Failures are expected so don't create any issues, please!"
          end
        end

        if formulae.blank?
          outdated = Formula.installed.select do |f|
            f.outdated?(fetch_head: args.fetch_HEAD?)
          end
        else
          outdated, not_outdated = formulae.partition do |f|
            f.outdated?(fetch_head: args.fetch_HEAD?)
          end

          not_outdated.each do |f|
            latest_keg = f.installed_kegs.max_by(&:scheme_and_version)
            if latest_keg.nil?
              ofail "#{f.full_specified_name} not installed"
            else
              opoo "#{f.full_specified_name} #{latest_keg.version} already installed" unless args.quiet?
            end
          end
        end

        return if outdated.blank?

        pinned = outdated.select(&:pinned?)
        outdated -= pinned
        formulae_to_install = outdated.map do |f|
          f_latest = f.latest_formula
          if f_latest.latest_version_installed?
            f
          else
            f_latest
          end
        end

        if pinned.any?
          message = "Not upgrading #{pinned.count} pinned #{Utils.pluralize("package", pinned.count)}:"
          # only fail when pinned formulae are named explicitly
          if formulae.any?
            ofail message
          else
            opoo message
          end
          puts pinned.map { |f| "#{f.full_specified_name} #{f.pkg_version}" } * ", "
        end

        if formulae_to_install.empty?
          oh1 "No packages to upgrade" if show_upgrade_summary
        elsif show_upgrade_summary
          verb = args.dry_run? ? "Would upgrade" : "Upgrading"
          oh1 "#{verb} #{formulae_to_install.count} outdated #{Utils.pluralize("package",
                                                                               formulae_to_install.count)}:"
          puts formula_upgrade_descriptions(formulae_to_install).join("\n") unless args.ask?
        end

        Install.perform_preinstall_checks_once

        formulae_installer = Upgrade.formula_installers(
          formulae_to_install,
          flags:                      args.flags_only,
          dry_run:                    args.dry_run?,
          force_bottle:               args.force_bottle?,
          build_from_source_formulae: args.build_from_source_formulae,
          interactive:                args.interactive?,
          keep_tmp:                   args.keep_tmp?,
          debug_symbols:              args.debug_symbols?,
          force:                      args.force?,
          overwrite:                  args.overwrite?,
          debug:                      args.debug?,
          quiet:                      args.quiet?,
          verbose:                    args.verbose?,
        )

        return if formulae_installer.blank?

        dependants = Upgrade.dependants(
          formulae_to_install,
          flags:                      args.flags_only,
          dry_run:                    args.dry_run?,
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

        # Main block: if asking the user is enabled, show dependency and size information.
        Install.ask_formulae(formulae_installer, dependants, args: args) if args.ask?

        FormulaeUpgradeContext.new(
          formulae_to_install:,
          formulae_installer:  formulae_installer,
          dependants:,
        )
      end

      sig { params(formulae: T::Array[Formula]).returns(T::Array[String]) }
      def formula_upgrade_descriptions(formulae)
        formulae.map do |formula|
          if formula.optlinked?
            "#{formula.full_specified_name} #{Keg.new(formula.opt_prefix).version} -> #{formula.pkg_version}"
          else
            "#{formula.full_specified_name} #{formula.pkg_version}"
          end
        end
      end

      sig {
        params(
          formulae:               T::Array[Formula],
          prefetch_only:          T::Boolean,
          use_prefetched:         T::Boolean,
          download_queue:         T.nilable(Homebrew::DownloadQueue),
          prefetch_names:         T.nilable(T::Array[String]),
          prefetch_upgrades:      T.nilable(T::Array[String]),
          show_upgrade_summary:   T::Boolean,
          show_downloads_heading: T::Boolean,
        ).returns(T::Boolean)
      }
      def upgrade_outdated_formulae!(formulae, prefetch_only: false, use_prefetched: false,
                                     download_queue: nil,
                                     prefetch_names: nil,
                                     prefetch_upgrades: nil,
                                     show_upgrade_summary: true,
                                     show_downloads_heading: true)
        return false if args.cask?

        use_prefetched_context = use_prefetched && @prefetched_formulae_upgrade_context
        context = if use_prefetched_context
          @prefetched_formulae_upgrade_context
        else
          formulae_upgrade_context(formulae, show_upgrade_summary:)
        end
        return false if context.blank?

        if prefetch_only
          prefetch_download_queue = download_queue || Homebrew.default_download_queue
          valid_formula_installers = Install.enqueue_formulae(context.formulae_installer,
                                                              download_queue: prefetch_download_queue)
          if show_downloads_heading
            Install.show_combined_fetch_downloads_heading(
              formula_names: valid_formula_installers.map { |fi| fi.formula.name },
            )
          end
          prefetch_names&.replace(valid_formula_installers.map { |fi| fi.formula.name })
          prefetch_upgrades&.replace(formula_upgrade_descriptions(valid_formula_installers.map(&:formula)))
          @prefetched_formulae_upgrade_context = FormulaeUpgradeContext.new(
            formulae_to_install: context.formulae_to_install,
            formulae_installer:  valid_formula_installers,
            dependants:          context.dependants,
          )
          return valid_formula_installers.present?
        end

        Upgrade.upgrade_formulae(
          context.formulae_installer,
          dry_run: args.dry_run?,
          verbose: args.verbose?,
          fetch:   !use_prefetched_context,
        )

        Upgrade.upgrade_dependents(
          context.dependants, context.formulae_to_install,
          flags:                      args.flags_only,
          dry_run:                    args.dry_run?,
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

        @prefetched_formulae_upgrade_context = nil if use_prefetched_context
        true
      end

      sig {
        params(casks: T::Array[Cask::Cask], download_queue: Homebrew::DownloadQueue,
               prefetch_names: T.nilable(T::Array[String]),
               prefetch_upgrades: T.nilable(T::Array[String]),
               show_downloads_heading: T::Boolean)
          .returns(T::Boolean)
      }
      def prefetch_outdated_casks!(casks, download_queue:, prefetch_names: nil,
                                   prefetch_upgrades: nil,
                                   show_downloads_heading: true)
        return false if args.formula?

        outdated_casks = Cask::Upgrade.outdated_casks(
          casks,
          args:,
          force:               args.force?,
          quiet:               true,
          greedy:              args.greedy?,
          greedy_latest:       args.greedy_latest?,
          greedy_auto_updates: args.greedy_auto_updates?,
        )
        return false if outdated_casks.empty?

        manual_installer_casks = outdated_casks.select do |cask|
          cask.artifacts.any? do |artifact|
            artifact.is_a?(Cask::Artifact::Installer) && artifact.manual_install
          end
        end
        outdated_casks -= manual_installer_casks
        return false if outdated_casks.empty?

        require "cask/installer"
        fetchable_cask_installers = outdated_casks.map do |cask|
          Cask::Installer.new(
            cask,
            binaries:       args.binaries?,
            verbose:        args.verbose?,
            force:          args.force?,
            skip_cask_deps: args.skip_cask_deps?,
            require_sha:    args.require_sha?,
            upgrade:        true,
            quarantine:     args.quarantine?,
            download_queue:,
            defer_fetch:    true,
          )
        end
        cask_names = outdated_casks.map(&:full_name)
        Install.enqueue_cask_installers(fetchable_cask_installers)
        prefetch_names&.replace(cask_names)
        prefetch_upgrades&.replace(
          outdated_casks.map { |cask| "#{cask.full_name} #{cask.installed_version} -> #{cask.version}" },
        )
        Install.show_combined_fetch_downloads_heading(cask_names:) if show_downloads_heading

        true
      rescue => e
        ofail e
        false
      end

      sig {
        params(casks: T::Array[Cask::Cask], skip_prefetch: T::Boolean,
               download_queue: T.nilable(Homebrew::DownloadQueue))
          .returns(T::Boolean)
      }
      def upgrade_outdated_casks!(casks, skip_prefetch: false,
                                  download_queue: nil)
        return false if args.formula?

        Install.ask_casks casks if args.ask?

        Cask::Upgrade.upgrade_casks!(
          *casks,
          force:                args.force?,
          greedy:               args.greedy?,
          greedy_latest:        args.greedy_latest?,
          greedy_auto_updates:  args.greedy_auto_updates?,
          dry_run:              args.dry_run?,
          binaries:             args.binaries?,
          quarantine:           args.quarantine?,
          require_sha:          args.require_sha?,
          skip_cask_deps:       args.skip_cask_deps?,
          verbose:              args.verbose?,
          quiet:                args.quiet?,
          skip_prefetch:,
          show_upgrade_summary: !skip_prefetch,
          download_queue:,
          args:,
        )
      rescue => e
        ofail e
        false
      end
    end
  end
end
