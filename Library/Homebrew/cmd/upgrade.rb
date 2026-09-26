# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula_installer"
require "install"
require "upgrade"
require "cask/download"
require "cask/installer"
require "cask/utils"
require "cask/upgrade"
require "api"
require "reinstall"
require "minimum_version"
require "trust"

module Homebrew
  module Cmd
    class UpgradeCmd < AbstractCommand
      class FormulaeUpgradeContext < T::Struct
        const :formulae_to_install, T::Array[Formula]
        const :formulae_installer, T::Array[FormulaInstaller]
        const :dependants, Homebrew::Upgrade::Dependents
        const :pinned_formulae, T::Array[Formula], default: []
        const :dependent_formulae_installer, T::Array[FormulaInstaller], default: []
      end

      class FinalUpgradeSummary < T::Struct
        prop :version_changes, T::Array[String], default: []
        prop :dependent_version_changes, T::Array[String], default: []
        prop :pinned_formulae, T::Array[String], default: []
        prop :pinned_casks, T::Array[String], default: []
        prop :deprecated, T::Array[String], default: []
        prop :disabled, T::Array[String], default: []
        prop :source_build_formulae, T::Array[String], default: []

        sig { returns(T::Array[String]) }
        def all_version_changes = version_changes + dependent_version_changes
      end

      cmd_args do
        description <<~EOS
          Upgrade outdated, unpinned packages using the same options they were originally installed with,
          plus any appended brew formula options. If <cask> or <formula> are specified, upgrade only the given
          <cask> or <formula> (unless they are pinned; see `pin`, `unpin`).

          Unless `$HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK` is set, `brew upgrade` or `brew reinstall` will be run for
          outdated dependents and dependents with broken linkage, respectively.

          Unless `$HOMEBREW_NO_INSTALL_CLEANUP` is set, `brew cleanup` will then be run for the
          upgraded formulae and casks or, every 30 days, for all packages.
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
        flag   "--minimum-version=", "--min-version=",
               description: "Only upgrade a named formula or cask with an installed version below the given " \
                            "minimum version."
        switch "--no-ask", "--yes", "-y",
               description: "Do not ask for confirmation before downloading and upgrading. Ask mode is the default.",
               env:         :no_ask
        switch "--ask",
               description: "Ask for confirmation before downloading and upgrading. " \
                            "Print the same plan as `--dry-run`, including available download sizes. " \
                            "When named arguments are provided, only prompts if the plan includes packages " \
                            "other than those arguments; if the requested formulae or casks are the only " \
                            "things to upgrade, it only prints the plan. With no named arguments, prompts if " \
                            "anything would be upgraded. The confirmation prompt is skipped without a TTY. " \
                            "This is the default unless `$HOMEBREW_NO_ASK` is set.",
               env:         :ask,
               replacement: "the default behaviour",
               odisabled:   true
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
                         "macOS, even if it would not normally be used for installation. " \
                         "Fail rather than build from source if a formula or dependency has no bottle.",
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
          [:switch, "--no-quit", {
            description: "Prevent running cask applications from being quit during upgrade.",
            env:         :no_upgrade_quit_casks,
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
        ].each do |args|
          options = args.pop
          send(*args, **options)
          conflicts "--formula", args.last
        end
        cask_options

        conflicts "--build-from-source", "--force-bottle"
        conflicts "--ask", "--no-ask"

        named_args [:installed_formula, :installed_cask]
      end

      sig { override.params(argv: T::Array[String]).void }
      def initialize(argv = ARGV.freeze)
        super
        @ask_prompt_required = T.let(false, T::Boolean)
        @upgraded_formulae = T.let([], T::Array[Formula])
        @upgraded_casks = T.let([], T::Array[Cask::Cask])
      end

      sig { override.void }
      def run
        if args.build_from_source? && args.named.empty?
          raise ArgumentError, "`--build-from-source` requires at least one formula"
        end
        raise UsageError, "`--minimum-version` requires exactly one formula or cask argument." if
          minimum_version.present? && args.named.length != 1

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
        prefetched_cask_upgrade_casks = T.let([], T::Array[Cask::Cask])
        prefetched_cask_installers = T.let([], T::Array[Cask::Installer])
        prefetched_cask_errors = T.let([], T::Array[StandardError])
        @final_upgrade_summary = T.let(FinalUpgradeSummary.new, T.nilable(FinalUpgradeSummary))
        @ask_prompt_required = false
        @upgraded_formulae.clear
        @upgraded_casks.clear
        ask = !args.no_ask? && !args.dry_run?
        skip_upgrades_after_failed_ask_preview = T.let(false, T::Boolean)

        if args.named.present?
          Homebrew::Trust.trust_fully_qualified_items!(args.named, type: args.only_formula_or_cask)

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

        if Homebrew::EnvConfig.verify_attestations?
          formulae = Homebrew::Attestation.sort_formulae_for_install(formulae)
        end

        formulae_prefetched = T.let(false, T::Boolean)
        prefetched_casks = T.let(false, T::Boolean)
        ask_upgrade_planned = T.let(false, T::Boolean)
        planned_fetch_names = T.let([], T::Array[String])
        shared_download_queue = T.let(nil, T.nilable(Homebrew::DownloadQueue))
        if ask
          unless only_upgrade_casks
            upgrade_outdated_formulae!(
              formulae,
              dry_run:              true,
              show_upgrade_summary: false,
            )
          end
          unless only_upgrade_formulae
            upgrade_outdated_casks!(
              casks,
              dry_run:              true,
              skip_prefetch:        false,
              show_upgrade_summary: false,
              download_queue:       nil,
            )
          end

          show_final_upgrade_summary(dry_run: true)
          planned_fetch_names = final_upgrade_summary.all_version_changes.map { |change| change.split.fetch(0) }
          if Install.ask_prompt_needed?(
            planned_names:   planned_fetch_names.map do |planned_name|
              formulae.find { |formula| formula.full_specified_name == planned_name }&.full_name || planned_name
            end,
            requested_names: args.named,
            force:           @ask_prompt_required,
            named:           args.named.present?,
          )
            Install.ask(action: "upgrade")
          end
          ask_upgrade_planned = final_upgrade_summary.all_version_changes.present?
          skip_upgrades_after_failed_ask_preview = Homebrew.failed? && !ask_upgrade_planned
          @final_upgrade_summary = FinalUpgradeSummary.new
        end

        if !args.dry_run? && (!ask || ask_upgrade_planned) && !(only_upgrade_formulae && only_upgrade_casks)
          shared_download_queue = Homebrew::DownloadQueue.new(pour: true)
          # The preview shown before the prompt already knows what will be
          # upgraded, so print the heading before the prefetch works it out again.
          early_fetch_heading = Install.combined_fetch_downloads_heading(formula_names: planned_fetch_names)
          shared_download_queue.print_heading(early_fetch_heading) if early_fetch_heading
          begin
            unless only_upgrade_casks
              formulae_prefetched = upgrade_outdated_formulae!(
                formulae,
                prefetch_only:        true,
                download_queue:       shared_download_queue,
                prefetch_names:       prefetched_formulae_names,
                prefetch_upgrades:    prefetched_formulae_upgrades,
                show_upgrade_summary: false,
              )
            end
            unless only_upgrade_formulae
              prefetched_casks = prefetch_outdated_casks!(
                casks,
                download_queue:      shared_download_queue,
                prefetch_names:      prefetched_cask_names,
                prefetch_upgrades:   prefetched_cask_upgrades,
                prefetch_casks:      prefetched_cask_upgrade_casks,
                prefetch_installers: prefetched_cask_installers,
                prefetch_errors:     prefetched_cask_errors,
              )
            end
            unless ask
              Cask::Upgrade.show_upgrade_summary(
                prefetched_formulae_upgrades + prefetched_cask_upgrades,
                dry_run: args.dry_run?,
              )
            end
            unless early_fetch_heading
              fetch_heading = Install.combined_fetch_downloads_heading(
                formula_names: prefetched_formulae_names,
                cask_names:    prefetched_cask_names,
              ) || "Fetching dependency downloads"
            end
            shared_download_queue.fetch(heading: fetch_heading)
            # Only redo the slower unprefetched fetch for the kind of package
            # that actually failed, so e.g. one bad bottle does not also
            # re-verify every already downloaded cask. The unprefetched fetch
            # must fetch failed formulae again from scratch, so they cannot
            # stay marked as already fetched.
            failed_cask_downloads, failed_formula_downloads =
              shared_download_queue.failed_downloads.partition { |download| download.is_a?(Cask::Download) }
            Install.unmark_failed_formulae(failed_formula_downloads)
            formulae_prefetched = false if failed_formula_downloads.any?
            prefetched_casks = false if failed_cask_downloads.any?
            if prefetched_casks
              Install.fetch_cask_dependencies(prefetched_cask_installers, download_queue: shared_download_queue)
            end
          ensure
            shared_download_queue.shutdown
          end
        end

        if !only_upgrade_casks && !skip_upgrades_after_failed_ask_preview
          upgrade_outdated_formulae!(
            formulae,
            use_prefetched:       formulae_prefetched,
            show_upgrade_summary: prefetched_formulae_upgrades.blank? && !args.dry_run? && !ask,
          )
        end
        if !only_upgrade_formulae && !skip_upgrades_after_failed_ask_preview
          if prefetched_casks
            upgrade_outdated_casks!(
              prefetched_cask_upgrade_casks,
              skip_prefetch:              true,
              show_upgrade_summary:       prefetched_cask_upgrades.blank? && !args.dry_run? && !ask,
              download_queue:             nil,
              prefetched_cask_errors:     prefetched_cask_errors,
              prefetched_cask_installers:,
            )
          else
            upgrade_outdated_casks!(
              casks,
              skip_prefetch:        false,
              show_upgrade_summary: prefetched_cask_upgrades.blank? && !args.dry_run? && !ask,
              download_queue:       nil,
            )
          end
        end

        unavailable_errors.each { |e| ofail e }

        Homebrew::Reinstall.reinstall_pkgconf_if_needed!(dry_run: args.dry_run?)

        Install.finish_installation(
          formulae:      @upgraded_formulae,
          casks:         @upgraded_casks,
          dry_run:       args.dry_run?,
          display_times: args.display_times?,
        )

        show_final_upgrade_summary
      end

      sig {
        params(formulae: T::Array[Formula], show_upgrade_summary: T::Boolean,
               dry_run: T::Boolean).returns(T.nilable(FormulaeUpgradeContext))
      }
      def formulae_upgrade_context(formulae, show_upgrade_summary: true, dry_run: args.dry_run?)
        if args.build_from_source?
          unless DevelopmentTools.installed?
            raise BuildFlagsError.new(["--build-from-source"], bottled: formulae.all?(&:bottled?))
          end

          unless Homebrew::EnvConfig.developer?
            opoo "building from source is not supported!"
            puts "You're on your own. Failures are expected so don't create any issues, please!"
          end
        end

        quiet = args.quiet? || (dry_run && !args.dry_run?)
        not_outdated = T.let([], T::Array[Formula])
        if formulae.blank?
          outdated = Formula.installed.select do |f|
            formula_outdated?(f)
          end
        elsif minimum_version.present?
          outdated, not_outdated = formulae.partition do |f|
            f.outdated?(fetch_head: args.fetch_HEAD?)
          end
          outdated, minimum_version_skipped = outdated.partition do |f|
            MinimumVersion.formula_outdated_kegs(f, minimum_version, fetch_head: args.fetch_HEAD?).present?
          end

          minimum_version_skipped.each do |f|
            next if quiet

            opoo "Not upgrading #{f.full_specified_name}, the installed version is not below " \
                 "the minimum version #{minimum_version}"
          end
        else
          outdated, not_outdated = formulae.partition do |f|
            formula_outdated?(f)
          end
        end

        if formulae.present?
          not_outdated.each do |f|
            latest_keg = f.installed_kegs.max_by(&:scheme_and_version)
            if latest_keg.nil?
              ofail "#{f.full_specified_name} not installed"
            else
              opoo "#{f.full_specified_name} #{latest_keg.version} already installed" unless quiet
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

        if formulae_to_install.empty?
          oh1 "No packages to upgrade" if show_upgrade_summary
        elsif show_upgrade_summary
          verb = dry_run ? "Would upgrade" : "Upgrading"
          oh1 "#{verb} #{formulae_to_install.count} outdated #{Utils.pluralize("package",
                                                                               formulae_to_install.count)}:"
          puts Upgrade.format_upgrade_summary(formula_upgrade_descriptions(formulae_to_install)).join("\n") if
            args.no_ask?
        end

        Install.perform_preinstall_checks_once

        formulae_installer = Upgrade.formula_installers(
          formulae_to_install,
          flags:                      args.flags_only,
          dry_run:,
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

        if formulae_installer.blank?
          return if formulae_to_install.present?
          return if pinned.blank?
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

        if formulae_installer.blank?
          return FormulaeUpgradeContext.new(
            formulae_to_install:,
            formulae_installer:  formulae_installer,
            dependants:          Homebrew::Upgrade::Dependents.new(upgradeable: [], pinned: [], skipped: []),
            pinned_formulae:     pinned,
          )
        end

        dependants = Upgrade.dependants(
          formulae_to_install,
          flags:                      args.flags_only,
          dry_run:,
          ask:                        !args.no_ask?,
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

        FormulaeUpgradeContext.new(
          formulae_to_install:,
          formulae_installer:  formulae_installer,
          dependants:,
          pinned_formulae:     pinned,
        )
      end

      sig { returns(FinalUpgradeSummary) }
      def final_upgrade_summary
        @final_upgrade_summary ||= T.let(FinalUpgradeSummary.new, T.nilable(FinalUpgradeSummary))
        @final_upgrade_summary
      end

      sig {
        params(
          context:                   FormulaeUpgradeContext,
          include_sizes:             T::Boolean,
          formulae_installer:        T.nilable(T::Array[FormulaInstaller]),
          version_changes:           T.nilable(T::Array[String]),
          dependent_version_changes: T.nilable(T::Array[String]),
        ).void
      }
      def record_formula_upgrade_summary(context, include_sizes: false, formulae_installer: nil, version_changes: nil,
                                         dependent_version_changes: nil)
        summary = final_upgrade_summary
        formulae_installer ||= context.formulae_installer
        upgrade_formulae = formulae_installer.map(&:formula)
        dependent_formulae = context.dependants.upgradeable
        summary.version_changes.concat(version_changes || formula_upgrade_descriptions(upgrade_formulae,
                                                                                       include_sizes:))
        summary.dependent_version_changes.concat(
          dependent_version_changes || formula_upgrade_descriptions(dependent_formulae, include_sizes:),
        )
        summary.pinned_formulae.concat((context.pinned_formulae + context.dependants.pinned).map do |formula|
          "#{formula.full_specified_name} #{formula.pkg_version}"
        end)

        formulae = context.formulae_to_install + context.pinned_formulae +
                   context.dependants.upgradeable + context.dependants.pinned
        summary.deprecated.concat(formulae.filter_map do |formula|
          formula.full_specified_name if formula.deprecated?
        end)
        summary.disabled.concat(formulae.filter_map do |formula|
          formula.full_specified_name if formula.disabled?
        end)
        summary.source_build_formulae.concat(formulae_installer.filter_map do |formula_installer|
          formula = formula_installer.formula
          next unless formula.core_formula?
          next if formula_installer.pour_bottle?

          formula.full_specified_name
        end)
      end

      sig { params(dry_run: T::Boolean).void }
      def show_final_upgrade_summary(dry_run: args.dry_run?)
        summary = final_upgrade_summary
        return if summary.all_version_changes.empty? &&
                  summary.pinned_formulae.empty? && summary.pinned_casks.empty? &&
                  summary.deprecated.empty? && summary.disabled.empty? && summary.source_build_formulae.empty?

        named = args.named.present?
        version_changes = named ? summary.version_changes : summary.all_version_changes
        if version_changes.present?
          version_change_count = version_changes.uniq.count
          show_final_upgrade_summary_section(
            "#{dry_run ? "Would upgrade" : "Upgraded"} #{version_change_count} " \
            "#{"requested " if named}outdated " \
            "#{Utils.pluralize("package", version_change_count)}",
            Upgrade.format_upgrade_summary(version_changes),
          )
        end
        if named && summary.dependent_version_changes.present?
          dependent_count = summary.dependent_version_changes.uniq.count
          show_final_upgrade_summary_section(
            "#{dry_run ? "Would upgrade" : "Upgraded"} #{dependent_count} " \
            "#{Utils.pluralize("dependent", dependent_count)}",
            Upgrade.format_upgrade_summary(summary.dependent_version_changes),
          )
        end
        if summary.pinned_formulae.present?
          pinned_count = summary.pinned_formulae.uniq.count
          show_final_upgrade_summary_section(
            "#{pinned_count} Pinned #{Utils.pluralize("formula", pinned_count)}",
            summary.pinned_formulae,
          )
        end
        if summary.pinned_casks.present?
          pinned_count = summary.pinned_casks.uniq.count
          show_final_upgrade_summary_section(
            "#{pinned_count} Pinned #{Utils.pluralize("cask", pinned_count)}",
            summary.pinned_casks,
          )
        end
        deprecate_disable_summary = summary.deprecated.map { |item| "#{item} (deprecated)" } +
                                    summary.disabled.map { |item| "#{item} (disabled)" }
        deprecate_disable_count = deprecate_disable_summary.uniq.count
        show_final_upgrade_summary_section(
          "#{deprecate_disable_count} Deprecated or disabled #{Utils.pluralize("package", deprecate_disable_count)}",
          deprecate_disable_summary,
        )
        source_build_count = summary.source_build_formulae.uniq.count
        if dry_run
          show_final_upgrade_summary_section(
            "#{source_build_count} homebrew/core " \
            "#{Utils.pluralize("formula", source_build_count)} that would build from source",
            summary.source_build_formulae,
          )
        else
          show_final_upgrade_summary_section(
            "#{source_build_count} homebrew/core #{Utils.pluralize("formula", source_build_count)} built from source",
            summary.source_build_formulae,
          )
        end
      end

      sig { params(formulae: T::Array[Formula], include_sizes: T::Boolean).returns(T::Array[String]) }
      def formula_upgrade_descriptions(formulae, include_sizes: false)
        formulae.map do |formula|
          if formula.optlinked?
            old_keg = Keg.new(formula.opt_prefix)
            old_version = old_keg.version
            new_version = formula_upgrade_display_version(formula, old_version)
            if include_sizes
              "#{formula.full_specified_name} #{old_version} -> " \
                "#{new_version}#{formula_upgrade_size(formula)}"
            else
              "#{formula.full_specified_name} #{old_version} -> #{new_version}"
            end
          elsif include_sizes
            "#{formula.full_specified_name} #{formula.pkg_version}#{formula_upgrade_size(formula)}"
          else
            "#{formula.full_specified_name} #{formula.pkg_version}"
          end
        end
      end

      sig {
        params(
          formulae:             T::Array[Formula],
          prefetch_only:        T::Boolean,
          use_prefetched:       T::Boolean,
          dry_run:              T::Boolean,
          download_queue:       T.nilable(Homebrew::DownloadQueue),
          prefetch_names:       T.nilable(T::Array[String]),
          prefetch_upgrades:    T.nilable(T::Array[String]),
          show_upgrade_summary: T::Boolean,
        ).returns(T::Boolean)
      }
      def upgrade_outdated_formulae!(formulae, prefetch_only: false, use_prefetched: false,
                                     dry_run: args.dry_run?,
                                     download_queue: nil,
                                     prefetch_names: nil,
                                     prefetch_upgrades: nil,
                                     show_upgrade_summary: true)
        return false if args.cask?

        use_prefetched_context = use_prefetched && @prefetched_formulae_upgrade_context
        context = if use_prefetched_context
          @prefetched_formulae_upgrade_context
        else
          formulae_upgrade_context(formulae, show_upgrade_summary:, dry_run:)
        end
        if context.blank?
          if prefetch_only
            @prefetched_formulae_upgrade_context = FormulaeUpgradeContext.new(
              formulae_to_install: [],
              formulae_installer:  [],
              dependants:          Upgrade::Dependents.new(upgradeable: [], pinned: [], skipped: []),
            )
            return true
          end
          return false
        end

        if prefetch_only
          prefetch_download_queue = download_queue || Homebrew::DownloadQueue.default
          dependent_formulae_installer = Upgrade.dependent_formula_installers(
            context.dependants,
            context.formulae_installer.map(&:formula),
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
          valid_formula_installers = Install.enqueue_formulae((context.formulae_installer +
                                                               dependent_formulae_installer)
                                                                .uniq { |fi| fi.formula.full_name },
                                                              download_queue: prefetch_download_queue)
          prefetch_names&.replace(valid_formula_installers.map { |fi| fi.formula.name })
          prefetch_upgrades&.replace(formula_upgrade_descriptions(valid_formula_installers.map(&:formula)))
          valid_dependent_formulae_installer = valid_formula_installers & dependent_formulae_installer
          @prefetched_formulae_upgrade_context = FormulaeUpgradeContext.new(
            formulae_to_install:          context.formulae_to_install,
            formulae_installer:           valid_formula_installers & context.formulae_installer,
            dependants:                   Upgrade::Dependents.new(
              upgradeable: valid_dependent_formulae_installer.map(&:formula),
              pinned:      context.dependants.pinned,
              skipped:     context.dependants.skipped,
            ),
            pinned_formulae:              context.pinned_formulae,
            dependent_formulae_installer: valid_dependent_formulae_installer,
          )
          return true
        end

        planned_formula_version_changes = formula_upgrade_descriptions(context.formulae_installer.map(&:formula),
                                                                       include_sizes: dry_run)
        dependent_formulae = context.dependants.upgradeable.dup
        planned_dependent_version_changes = formula_upgrade_descriptions(dependent_formulae,
                                                                         include_sizes: dry_run)
        if dry_run
          record_formula_upgrade_summary(context,
                                         version_changes:           planned_formula_version_changes,
                                         dependent_version_changes: planned_dependent_version_changes)
        end
        if !args.no_ask? && dry_run && args.named.present? &&
           Install.formulae_ask_prompt_needed?(context.formulae_installer, context.dependants)
          @ask_prompt_required = true
        end

        skip_formula_names = if dry_run
          (context.formulae_installer.map(&:formula) + context.dependants.upgradeable)
            .uniq(&:full_name)
            .map(&:full_name)
        else
          []
        end

        upgraded_formula_installers = Upgrade.upgrade_formulae(
          context.formulae_installer,
          dry_run:,
          verbose:            args.verbose?,
          fetch:              !use_prefetched_context,
          cleanup:            false,
          skip_formula_names:,
        )

        prefetched_dependent_formulae_installer = if use_prefetched_context
          context.dependent_formulae_installer
        end
        upgraded_dependent_formulae = Upgrade.upgrade_dependents(
          context.dependants, context.formulae_to_install,
          flags:                         args.flags_only,
          dry_run:,
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
          prefetched_formula_installers: prefetched_dependent_formulae_installer,
          skip_formula_names:
        )

        unless dry_run
          @upgraded_formulae.concat(upgraded_formula_installers.map(&:formula) + upgraded_dependent_formulae)
                            .uniq!(&:full_name)
          upgraded_formulae_by_identity = T.let({}.compare_by_identity, T::Hash[Formula, T::Boolean])
          (upgraded_formula_installers.map(&:formula) + upgraded_dependent_formulae).each do |formula|
            upgraded_formulae_by_identity[formula] = true
          end
          formula_version_changes =
            context.formulae_installer.map(&:formula).each_with_index.filter_map do |formula, index|
              planned_formula_version_changes.fetch(index) if upgraded_formulae_by_identity.key?(formula)
            end
          dependent_version_changes = dependent_formulae.each_with_index.filter_map do |formula, index|
            planned_dependent_version_changes.fetch(index) if upgraded_formulae_by_identity.key?(formula)
          end
          record_formula_upgrade_summary(
            context,
            formulae_installer:        upgraded_formula_installers,
            version_changes:           formula_version_changes,
            dependent_version_changes:,
          )
        end

        @prefetched_formulae_upgrade_context = nil if use_prefetched_context
        true
      end

      sig {
        params(casks: T::Array[Cask::Cask], download_queue: Homebrew::DownloadQueue,
               prefetch_names: T.nilable(T::Array[String]),
               prefetch_upgrades: T.nilable(T::Array[String]),
               prefetch_casks: T.nilable(T::Array[Cask::Cask]),
               prefetch_installers: T.nilable(T::Array[Cask::Installer]),
               prefetch_errors: T.nilable(T::Array[StandardError]))
          .returns(T::Boolean)
      }
      def prefetch_outdated_casks!(casks, download_queue:, prefetch_names: nil,
                                   prefetch_upgrades: nil, prefetch_casks: nil, prefetch_installers: nil,
                                   prefetch_errors: nil)
        return false if args.formula?

        casks = minimum_version_casks(casks, quiet: true)
        return false if minimum_version.present? && casks.empty?

        outdated_casks = Cask::Upgrade.outdated_casks(
          casks,
          args:,
          force:               args.force?,
          quiet:               true,
          greedy:              args.greedy?,
          greedy_latest:       args.greedy_latest?,
          greedy_auto_updates: args.greedy_auto_updates?,
        )
        return true if outdated_casks.empty?

        manual_installer_casks = outdated_casks.select do |cask|
          cask.artifacts.any? do |artifact|
            artifact.is_a?(Cask::Artifact::Installer) && artifact.manual_install
          end
        end
        outdated_casks -= manual_installer_casks
        return false if outdated_casks.empty?

        require "cask/installer"
        fetchable_cask_installers = []
        outdated_casks.select! do |cask|
          installer = Cask::Installer.new(
            cask,
            binaries:       args.binaries?,
            verbose:        args.verbose?,
            force:          args.force?,
            skip_cask_deps: args.skip_cask_deps?,
            require_sha:    args.require_sha?,
            upgrade:        true,
            download_queue:,
            defer_fetch:    true,
          )
          begin
            installer.check_requirements
          rescue Cask::CaskError => e
            prefetch_errors&.push(e)
            next false
          end

          fetchable_cask_installers << installer
          true
        end
        return prefetch_errors.present? if outdated_casks.empty?

        valid_cask_installers = Install.enqueue_cask_installers(fetchable_cask_installers)
        valid_casks = valid_cask_installers.map(&:cask)
        prefetch_installers&.replace(valid_cask_installers)
        prefetch_casks&.replace(valid_casks)
        prefetch_names&.replace(valid_casks.map(&:full_name))
        prefetch_upgrades&.replace(
          valid_casks.map { |cask| "#{cask.full_name} #{cask.installed_version} -> #{cask.version}" },
        )
        true
      rescue => e
        ofail e
        false
      end

      sig {
        params(casks: T::Array[Cask::Cask], skip_prefetch: T::Boolean, show_upgrade_summary: T::Boolean,
               dry_run: T::Boolean,
               download_queue: T.nilable(Homebrew::DownloadQueue),
               prefetched_cask_errors: T.nilable(T::Array[StandardError]),
               prefetched_cask_installers: T.nilable(T::Array[Cask::Installer]))
          .returns(T::Boolean)
      }
      def upgrade_outdated_casks!(casks, skip_prefetch: false, show_upgrade_summary: true,
                                  dry_run: args.dry_run?,
                                  download_queue: nil, prefetched_cask_errors: nil,
                                  prefetched_cask_installers: nil)
        return false if args.formula?

        quiet = args.quiet? || (dry_run && !args.dry_run?)
        casks = minimum_version_casks(casks, quiet:)
        return false if minimum_version.present? && casks.empty?

        if skip_prefetch && casks.empty?
          prefetched_cask_errors&.each { |error| ofail error }
          return false
        end

        Cask::Upgrade.upgrade_casks!(
          *casks,
          force:                      args.force?,
          greedy:                     args.greedy?,
          greedy_latest:              args.greedy_latest?,
          greedy_auto_updates:        args.greedy_auto_updates?,
          dry_run:,
          binaries:                   args.binaries?,
          require_sha:                args.require_sha?,
          skip_cask_deps:             args.skip_cask_deps?,
          quit:                       !args.no_quit?,
          verbose:                    args.verbose?,
          quiet:,
          skip_prefetch:,
          show_upgrade_summary:,
          download_queue:,
          summary_upgrades:           final_upgrade_summary.version_changes,
          summary_pinned:             final_upgrade_summary.pinned_casks,
          summary_deprecated:         final_upgrade_summary.deprecated,
          summary_disabled:           final_upgrade_summary.disabled,
          prefetched_errors:          prefetched_cask_errors,
          upgraded_casks:             @upgraded_casks,
          prefetched_cask_installers:,
          args:,
        )
      rescue => e
        ofail e
        false
      end

      private

      sig { returns(T.nilable(String)) }
      def minimum_version = args.minimum_version || args.min_version

      sig { params(formula: Formula).returns(T::Boolean) }
      def formula_outdated?(formula)
        outdated = formula.outdated?(fetch_head: args.fetch_HEAD?)
        return false if outdated && fetched_head_formula_current?(formula)

        version = minimum_version
        return outdated if version.blank?

        outdated && MinimumVersion.formula_outdated_kegs(formula, version, fetch_head: args.fetch_HEAD?).present?
      end

      sig { params(formula: Formula).returns(T::Boolean) }
      def fetched_head_formula_current?(formula)
        return false unless args.fetch_HEAD?
        return false unless formula.head?
        return false unless formula.optlinked?

        old_version = Keg.new(formula.opt_prefix).version
        return false unless old_version.head?

        formula.latest_head_pkg_version(fetch_head: true).to_s == old_version.to_s
      end

      sig { params(casks: T::Array[Cask::Cask], quiet: T::Boolean).returns(T::Array[Cask::Cask]) }
      def minimum_version_casks(casks, quiet: args.quiet?)
        version = minimum_version
        return casks if version.blank?

        casks.select do |cask|
          if MinimumVersion.cask_installed_below?(cask, version)
            true
          else
            unless quiet
              opoo "Not upgrading #{cask.token}, the installed version is not below the minimum version #{version}"
            end
            false
          end
        end
      end

      sig { params(title: String, items: T::Array[String]).void }
      def show_final_upgrade_summary_section(title, items)
        items = items.uniq
        return if items.empty?

        oh1 title
        puts items.join("\n")
      end

      sig { params(formula: Formula, old_version: PkgVersion).returns(String) }
      def formula_upgrade_display_version(formula, old_version)
        return formula.pkg_version.to_s if !old_version.head? || !formula.head?
        return formula.pkg_version.to_s if formula.pkg_version.to_s != old_version.to_s
        return "latest HEAD" unless args.fetch_HEAD?

        latest_head_version = formula.latest_head_pkg_version(fetch_head: true)
        return "latest HEAD" if latest_head_version.to_s == old_version.to_s

        latest_head_version.to_s
      end

      sig { params(formula: Formula).returns(String) }
      def formula_upgrade_size(formula)
        return "" if args.build_from_source_formulae.include?(formula.name)

        bottle = formula.bottle
        return "" unless bottle

        bottle.fetch_tab(quiet: !args.debug?)
        return "" unless (download_size = bottle.bottle_size)

        " (#{Formatter.disk_usage_readable(download_size.to_i)})"
      end
    end
  end
end
