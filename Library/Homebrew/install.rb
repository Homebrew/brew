# typed: strict
# frozen_string_literal: true

require "utils/text"

require "diagnostic"
require "diagnostic/finding"
require "fileutils"
require "hardware"
require "development_tools"
require "upgrade"
require "download_queue"
require "ask"
require "cleanup"
require "messages"
require "utils/output"
require "utils/topological_hash"
require "install/check"
require "api/source_download"

module Homebrew
  # Helper module for performing (pre-)install checks.
  module Install
    extend Utils::Output::Mixin

    DependencySummary = T.type_alias { T::Hash[Symbol, T::Array[String]] }

    class << self
      sig { params(all_fatal: T::Boolean).void }
      def perform_preinstall_checks_once(all_fatal: false)
        @perform_preinstall_checks_once ||= T.let({}, T.nilable(T::Hash[T::Boolean, TrueClass]))
        @perform_preinstall_checks_once[all_fatal] ||= begin
          perform_preinstall_checks(all_fatal:)
          true
        end
      end

      sig { params(cc: T.nilable(String)).void }
      def check_cc_argv(cc)
        return unless cc

        opoo "You passed `--cc=#{cc}`."
        Diagnostic.support_tiers << 3
      end

      sig { params(all_fatal: T::Boolean).void }
      def perform_build_from_source_checks(all_fatal: false)
        Diagnostic.checks(:fatal_build_from_source_checks)
        Diagnostic.checks(:build_from_source_checks, fatal: all_fatal)
      end

      sig { void }
      def global_post_install; end

      sig { void }
      def check_prefix; end

      sig {
        params(formulae_to_install: T::Array[Formula], installed_on_request: T::Boolean,
               build_bottle: T::Boolean, force_bottle: T::Boolean,
               bottle_arch: T.nilable(String), ignore_deps: T::Boolean, only_deps: T::Boolean,
               include_test_formulae: T::Array[String], build_from_source_formulae: T::Array[String],
               cc: T.nilable(String), git: T::Boolean, interactive: T::Boolean, keep_tmp: T::Boolean,
               debug_symbols: T::Boolean, force: T::Boolean, overwrite: T::Boolean, debug: T::Boolean,
               quiet: T::Boolean, verbose: T::Boolean, dry_run: T::Boolean, skip_post_install: T::Boolean,
               skip_link: T::Boolean).returns(T::Array[FormulaInstaller])
      }
      def formula_installers(
        formulae_to_install,
        installed_on_request: true,
        build_bottle: false,
        force_bottle: false,
        bottle_arch: nil,
        ignore_deps: false,
        only_deps: false,
        include_test_formulae: [],
        build_from_source_formulae: [],
        cc: nil,
        git: false,
        interactive: false,
        keep_tmp: false,
        debug_symbols: false,
        force: false,
        overwrite: false,
        debug: false,
        quiet: false,
        verbose: false,
        dry_run: false,
        skip_post_install: false,
        skip_link: false
      )
        formulae_to_install.filter_map do |formula|
          Migrator.migrate_if_needed(formula, force:, dry_run:)
          build_options = formula.build

          FormulaInstaller.new(
            formula,
            options:                    build_options.used_options,
            installed_on_request:,
            build_bottle:,
            force_bottle:,
            bottle_arch:,
            ignore_deps:,
            only_deps:,
            include_test_formulae:,
            build_from_source_formulae:,
            cc:,
            git:,
            interactive:,
            keep_tmp:,
            debug_symbols:,
            force:,
            overwrite:,
            debug:,
            quiet:,
            verbose:,
            skip_post_install:,
            skip_link:,
          )
        end
      end

      sig {
        params(
          formula_installers:      T::Array[FormulaInstaller],
          download_queue:          T.nilable(Homebrew::DownloadQueue),
          fetch_after_enqueue:     T::Boolean,
          shutdown_download_queue: T::Boolean,
          show_downloads_heading:  T::Boolean,
        ).returns(T::Array[FormulaInstaller])
      }
      def fetch_formulae(
        formula_installers,
        download_queue: nil,
        fetch_after_enqueue: true,
        shutdown_download_queue: true,
        show_downloads_heading: true
      )
        return formula_installers if formula_installers.empty?

        download_queue = T.let(download_queue || Homebrew::DownloadQueue.new(pour: true), Homebrew::DownloadQueue)

        begin
          valid_formula_installers = prelude_fetch_formulae(formula_installers, download_queue:)
          # Wait on just the bottle manifests dependency resolution needs so
          # in-flight bottles are only reported under the downloads heading.
          download_queue.fetch(only: Resource::BottleManifest, heading: "Downloading bottle manifests",
                               allow_failures: true)

          [:prelude, :enqueue_fetch].each do |step|
            valid_formula_installers = select_formula_installers(valid_formula_installers, step:)
            next if step == :enqueue_fetch && !fetch_after_enqueue

            if step == :prelude
              download_queue.fetch(only: Resource::BottleManifest, heading: "Downloading bottle manifests",
                                   allow_failures: true)
            else
              heading = if show_downloads_heading
                combined_fetch_downloads_heading(formula_names: valid_formula_installers.map { |fi| fi.formula.name })
              end
              download_queue.fetch(heading:)
              valid_formula_installers = reject_failed_downloads(valid_formula_installers, download_queue:)
            end
          end
        ensure
          download_queue.shutdown if shutdown_download_queue
        end

        valid_formula_installers
      end

      # A failed download has already been reported, so skip installing its
      # formula rather than failing a second time on the missing or known-bad
      # download, while still installing everything else.
      sig {
        params(formula_installers: T::Array[FormulaInstaller],
               download_queue:     Homebrew::DownloadQueue).returns(T::Array[FormulaInstaller])
      }
      def reject_failed_downloads(formula_installers, download_queue:)
        failed_full_names = unmark_failed_formulae(download_queue.failed_downloads)
        return formula_installers if failed_full_names.empty?

        formula_installers.reject { |fi| failed_full_names.include?(fi.formula.full_name) }
      end

      # A formula whose download failed must not stay marked as fetched:
      # `FormulaInstaller#enqueue_fetch` marks formulae as fetched when their
      # downloads are enqueued, so a later retry pass would otherwise skip
      # fetching entirely and install from a known-bad cached download without
      # any checksum verification (issue 23714).
      sig { params(downloadables: T::Array[Downloadable]).returns(T::Array[String]) }
      def unmark_failed_formulae(downloadables)
        failed_full_names = downloadables.filter_map do |downloadable|
          owner = case downloadable
          when Bottle
            downloadable.resource.owner
          when Resource
            downloadable.owner
          when Homebrew::API::SourceDownload
            downloadable.formula
          end
          owner = owner.owner if owner.is_a?(SoftwareSpec)
          owner.full_name if owner.is_a?(Formula)
        end

        FormulaInstaller.fetched.delete_if { |formula| failed_full_names.include?(formula.full_name) }
        failed_full_names
      end

      sig {
        params(
          formula_installers: T::Array[FormulaInstaller],
          download_queue:     Homebrew::DownloadQueue,
          metadata_only:      T::Boolean,
        ).returns(T::Array[FormulaInstaller])
      }
      def prelude_fetch_formulae(formula_installers, download_queue:, metadata_only: false)
        formula_installers.each do |fi|
          fi.download_queue = download_queue
        end

        # Only pass the keyword when limiting the fetch so mocks and
        # overrides expecting the historical no-argument call keep working.
        action = ->(fi) { metadata_only ? fi.prelude_fetch(metadata_only: true) : fi.prelude_fetch }
        select_formula_installers(formula_installers, action:)
      end

      sig {
        params(
          formula_installers: T::Array[FormulaInstaller],
          step:               T.nilable(Symbol),
          action:             T.nilable(T.proc.params(formula_installer: FormulaInstaller).void),
        ).returns(T::Array[FormulaInstaller])
      }
      def select_formula_installers(formula_installers, step: nil, action: nil)
        formula_installers.select do |fi|
          if action
            action.call(fi)
          elsif step
            fi.public_send(step)
          end
          true
        rescue CannotInstallFormulaError => e
          ofail e.message
          false
        rescue => e
          ofail "#{fi.formula}: #{e}"
          false
        end
      end

      sig { params(formula_installers: T::Array[FormulaInstaller], download_queue: Homebrew::DownloadQueue).returns(T::Array[FormulaInstaller]) }
      def enqueue_formulae(formula_installers, download_queue:)
        fetch_formulae(
          formula_installers,
          download_queue:,
          fetch_after_enqueue:     false,
          shutdown_download_queue: false,
          show_downloads_heading:  false,
        )
      end

      sig { params(formula_names: T::Array[String], cask_names: T::Array[String]).returns(T.nilable(String)) }
      def combined_fetch_downloads_heading(formula_names: [], cask_names: [])
        combined_fetch_targets = formula_names.map { |name| Formatter.identifier(name) } +
                                 cask_names.map { |name| Formatter.identifier(name) }
        return if combined_fetch_targets.empty?

        "Fetching downloads for: #{Utils::Text.to_sentence(combined_fetch_targets)}"
      end

      # Leave the cask downloads queued so the caller fetches them alongside
      # any formula bottles under one heading instead of draining them first.
      sig { params(cask_installers: T::Array[Cask::Installer]).returns(T::Array[Cask::Installer]) }
      def enqueue_cask_installers(cask_installers)
        cask_installers.select do |cask_installer|
          cask_installer.enqueue_downloads
          true
        rescue => e
          ofail "#{cask_installer.cask}: #{e}"
          false
        end
      end

      # Cask dependencies are resolved from the downloaded container, so they
      # can only be queued once the cask downloads above have been fetched.
      sig { params(cask_installers: T::Array[Cask::Installer], download_queue: Homebrew::DownloadQueue).void }
      def fetch_cask_dependencies(cask_installers, download_queue:)
        return if cask_installers.empty?

        mark_failed_cask_downloads(cask_installers, download_queue:)
        cask_installers.each do |cask_installer|
          cask_installer.enqueue_dependency_downloads
        rescue => e
          ofail "#{cask_installer.cask}: #{e}"
        end
        download_queue.fetch(heading: "Fetching dependency downloads")
        mark_failed_cask_downloads(cask_installers, download_queue:)
      end

      sig { params(cask_installers: T::Array[Cask::Installer], download_queue: Homebrew::DownloadQueue).void }
      def mark_failed_cask_downloads(cask_installers, download_queue:)
        failed_downloads = download_queue.failed_downloads
        return if failed_downloads.empty?

        cask_installers.each do |cask_installer|
          next if cask_installer.download_failed?

          if failed_downloads.include?(cask_installer.downloader)
            cask_installer.download_failed!
          else
            mark_failed_cask_downloads(cask_installer.dependency_cask_installers, download_queue:)
          end
        end
      end

      sig {
        params(
          formulae:      T::Array[Formula],
          casks:         T::Array[Cask::Cask],
          dry_run:       T::Boolean,
          display_times: T::Boolean,
        ).void
      }
      def finish_installation(formulae:, casks:, dry_run: false, display_times: false)
        Cleanup.install_clean!(formulae:, casks:) unless dry_run
        Cleanup.periodic_clean!(dry_run:)
        Homebrew.messages.display_messages(force_caveats: true, display_times:)
      end

      sig {
        params(formula_installers: T::Array[FormulaInstaller], installed_on_request: T::Boolean,
               build_bottle: T::Boolean, force_bottle: T::Boolean,
               bottle_arch: T.nilable(String), ignore_deps: T::Boolean, only_deps: T::Boolean,
               include_test_formulae: T::Array[String], build_from_source_formulae: T::Array[String],
               cc: T.nilable(String), git: T::Boolean, interactive: T::Boolean, keep_tmp: T::Boolean,
               debug_symbols: T::Boolean, force: T::Boolean, overwrite: T::Boolean, debug: T::Boolean,
               quiet: T::Boolean, verbose: T::Boolean, dry_run: T::Boolean,
               dry_run_action: String, skip_post_install: T::Boolean, skip_link: T::Boolean,
               cleanup: T::Boolean).returns(T::Array[Formula])
      }
      def install_formulae(
        formula_installers,
        installed_on_request: true,
        build_bottle: false,
        force_bottle: false,
        bottle_arch: nil,
        ignore_deps: false,
        only_deps: false,
        include_test_formulae: [],
        build_from_source_formulae: [],
        cc: nil,
        git: false,
        interactive: false,
        keep_tmp: false,
        debug_symbols: false,
        force: false,
        overwrite: false,
        debug: false,
        quiet: false,
        verbose: false,
        dry_run: false,
        dry_run_action: "install",
        skip_post_install: false,
        skip_link: false,
        cleanup: true
      )
        return [] if formula_installers.empty?

        if dry_run
          groups = formula_installers.reject(&:only_deps?).map(&:formula).group_by do |formula|
            installed_version = Upgrade.installed_version(formula) if dry_run_action == "install"
            if installed_version && installed_version != formula.pkg_version
              "upgrade"
            else
              dry_run_action
            end
          end
          groups.keys.sort.each do |action|
            group = groups.fetch(action)
            ohai "Would #{action} #{Utils.pluralize("formula", group.count, include_count: true)}:"
            puts Upgrade.format_upgrade_summary(group.map do |formula|
              if action == "upgrade"
                Upgrade.formula_upgrade_description(formula)
              else
                "#{formula.full_specified_name} #{formula.pkg_version}"
              end
            end)
          end

          formula_installers.each do |fi|
            next if fi.ignore_deps?

            print_dry_run_dependencies(fi.formula, fi.compute_dependencies, &:name)
          end
          return []
        end

        installed_formulae = T.let([], T::Array[Formula])
        formula_installers.each do |fi|
          formula = fi.formula
          upgrade = formula.linked? && formula.outdated? && !formula.head? && !Homebrew::EnvConfig.no_install_upgrade?
          install_formula(fi, upgrade:)
          Cleanup.install_formula_clean!(formula) if cleanup
          installed_formulae << formula
        rescue BuildError => e
          require "utils/analytics"

          Utils::Analytics.report_build_error(e)
          e.dump(verbose:)
          Homebrew.failed = true
        rescue => e
          # Keep a single failed install (e.g. a bottle that fails to extract)
          # from aborting the rest of the batch while still failing the run.
          ofail "#{fi.formula.full_specified_name}: #{e}"
        end
        installed_formulae
      end

      sig {
        params(
          formula:            Formula,
          dependencies:       T::Array[Dependency],
          skip_formula_names: T::Array[String],
          dependency_summary: T.nilable(DependencySummary),
          _block:             T.proc.params(arg0: Formula).returns(String),
        ).void
      }
      def print_dry_run_dependencies(formula, dependencies, skip_formula_names: [], dependency_summary: nil, &_block)
        return if dependencies.empty?

        entries = dependencies.filter_map do |dep|
          dependency = dep.to_formula
          next if skip_formula_names.include?(dependency.full_name)

          [dependency.any_version_installed?, yield(dependency)]
        end

        upgrade, install = entries.partition(&:first)
        summary = { install: install.map(&:last), upgrade: upgrade.map(&:last) }
        if dependency_summary
          summary.each { |verb, group| dependency_summary.fetch(verb).concat(group) }
        else
          print_dry_run_dependency_summary(summary, formula:)
        end
      end

      sig { params(summary: DependencySummary, formula: T.nilable(Formula)).void }
      def print_dry_run_dependency_summary(summary, formula: nil)
        { install: summary.fetch(:install), upgrade: summary.fetch(:upgrade) }.each do |verb, group|
          group = group.uniq
          next if group.empty?

          ohai "Would #{verb} #{Utils.pluralize("dependency", group.count, include_count: true)}" \
               "#{" for #{formula.name}" if formula}:"
          puts Upgrade.format_upgrade_summary(group)
        end
      end

      # If asking the user is enabled, show dry-run information.
      sig {
        params(
          formulae_installer:         T::Array[FormulaInstaller],
          dependants:                 Homebrew::Upgrade::Dependents,
          flags:                      T::Array[String],
          force_bottle:               T::Boolean,
          build_from_source_formulae: T::Array[String],
          interactive:                T::Boolean,
          keep_tmp:                   T::Boolean,
          debug_symbols:              T::Boolean,
          force:                      T::Boolean,
          debug:                      T::Boolean,
          quiet:                      T::Boolean,
          verbose:                    T::Boolean,
          prompt:                     T::Boolean,
          action:                     String,
        ).void
      }
      def ask_formulae(formulae_installer, dependants,
                       flags: [],
                       force_bottle: false,
                       build_from_source_formulae: [],
                       interactive: false,
                       keep_tmp: false,
                       debug_symbols: false,
                       force: false,
                       debug: false,
                       quiet: false,
                       verbose: false,
                       prompt: true,
                       action: "installation")
        return if formulae_installer.empty?

        formula_names = formulae_installer.map { |formula_installer| formula_installer.formula.full_name }

        install_formulae(formulae_installer, dry_run: true, dry_run_action: dry_run_action(action))

        Upgrade.upgrade_dependents(
          Homebrew::Upgrade::Dependents.new(
            upgradeable: dependants.upgradeable.dup,
            pinned:      dependants.pinned.dup,
            skipped:     dependants.skipped.dup,
          ),
          formulae_installer.map(&:formula),
          flags:,
          dry_run:                    true,
          force_bottle:,
          build_from_source_formulae:,
          interactive:,
          keep_tmp:,
          debug_symbols:,
          force:,
          debug:,
          quiet:,
          verbose:,
        )

        ask_input(action:) if prompt && ask_prompt_needed?(
          planned_names:   formula_names,
          requested_names: formula_names,
          force:           formulae_ask_prompt_needed?(formulae_installer, dependants),
        )
      end

      sig {
        params(
          casks:          T::Array[Cask::Cask],
          action:         String,
          prompt:         T::Boolean,
          skip_cask_deps: T::Boolean,
        ).void
      }
      def ask_casks(casks, action: "installation", prompt: true, skip_cask_deps: false)
        return if casks.empty?

        cask_names = casks.map(&:full_name)
        dependency_names = print_dry_run_casks(casks, action: dry_run_action(action), skip_cask_deps:)

        ask_input(action:) if prompt && ask_prompt_needed?(
          planned_names:   cask_names + dependency_names,
          requested_names: cask_names,
        )
      end

      sig {
        params(
          casks:             T::Array[Cask::Cask],
          action:            String,
          skip_cask_deps:    T::Boolean,
          include_installed: T::Boolean,
        ).returns(T::Array[String])
      }
      def print_dry_run_casks(casks, action: "install", skip_cask_deps: false, include_installed: true)
        if (casks_to_print = (include_installed ? casks : casks.reject(&:installed?)).presence)
          ohai "Would #{action} #{::Utils.pluralize("cask", casks_to_print.count, include_count: true)}:"
          puts casks_to_print.map(&:full_name).join(" ")
        end

        casks.flat_map do |cask|
          dep_names = T.let([], T::Array[String])
          unless skip_cask_deps
            dep_names.concat(
              ::Utils::TopologicalHash.graph_package_dependencies([cask]).tsort.grep(Cask::Cask).filter_map do |dep|
                next if dep.full_name == cask.full_name
                next if dep.installed?

                dep.full_name
              end,
            )
          end
          dep_names.concat(
            CaskDependent.new(cask)
                         .runtime_dependencies(read_from_tab: false, undeclared: false)
                         .reject(&:installed?)
                         .map(&:name),
          )
          dep_names.uniq!
          next [] if dep_names.blank?

          ohai "Would install #{::Utils.pluralize("dependency", dep_names.count, include_count: true)} " \
               "for #{cask.full_name}:"
          puts dep_names.join(" ")
          dep_names
        end
      end

      sig {
        params(
          planned_names:   T::Array[String],
          requested_names: T::Array[String],
          force:           T::Boolean,
          named:           T::Boolean,
        ).returns(T::Boolean)
      }
      def ask_prompt_needed?(planned_names:, requested_names:, force: false, named: true)
        return false if planned_names.empty?
        return true if force
        return true unless named

        planned_names.any? { |planned_name| requested_names.exclude?(planned_name) }
      end

      sig {
        params(
          formulae_installer: T::Array[FormulaInstaller],
          dependants:         Homebrew::Upgrade::Dependents,
        ).returns(T::Boolean)
      }
      def formulae_ask_prompt_needed?(formulae_installer, dependants)
        formulae_installer.any? do |formula_installer|
          !formula_installer.ignore_deps? && formula_installer.compute_dependencies.present?
        end ||
          dependants.upgradeable.present?
      end

      sig { params(formula_installer: FormulaInstaller, upgrade: T::Boolean).void }
      def install_formula(formula_installer, upgrade:)
        formula = formula_installer.formula

        formula_installer.check_installation_already_attempted

        if upgrade
          Upgrade.print_upgrade_message(formula, formula_installer.options)

          kegs = Upgrade.outdated_kegs(formula)
          linked_kegs = kegs.select(&:linked?)
        else
          formula.print_tap_action
        end

        # first we unlink the currently active keg for this formula otherwise it is
        # possible for the existing build to interfere with the build we are about to
        # do! Seriously, it happens!
        kegs.each(&:unlink) if kegs.present?

        formula_installer.install
        formula_installer.finish
      rescue FormulaInstallationAlreadyAttemptedError
        # We already attempted to upgrade f as part of the dependency tree of
        # another formula. In that case, don't generate an error, just move on.
        nil
      ensure
        # restore previous installation state if build failed
        begin
          linked_kegs&.each(&:link) unless formula&.latest_version_installed?
        rescue
          nil
        end
      end

      sig { params(action: String).void }
      def ask(action: "installation")
        ask_input(action:)
      end

      sig { params(all_fatal: T::Boolean).void }
      def perform_preinstall_checks(all_fatal: false)
        check_prefix
        check_cpu
        attempt_directory_creation
        Diagnostic.checks(:supported_configuration_checks, fatal: all_fatal)
        Diagnostic.checks(:preinstall_checks, fatal: false)
        Diagnostic.checks(:fatal_preinstall_checks)
      end

      private

      sig { params(action: String).returns(String) }
      def dry_run_action(action)
        case action
        when "reinstallation"
          "reinstall"
        when "upgrade"
          "upgrade"
        else
          "install"
        end
      end

      sig { params(formula: Formula).returns(T::Array[Keg]) }
      def outdated_kegs(formula)
        [formula, *formula.old_installed_formulae].map(&:linked_keg)
                                                  .select(&:directory?)
                                                  .map { |k| Keg.new(Utils::Path.resolved_path(k)) }
      end

      sig { void }
      def attempt_directory_creation
        Keg.must_exist_directories.each do |dir|
          FileUtils.mkdir_p(dir) unless dir.exist?
        rescue
          nil
        end
      end

      sig { void }
      def check_cpu
        return unless Hardware::CPU.ppc?

        odie <<~EOS
          Sorry, Homebrew does not support your computer's CPU architecture!
          For PowerPC Mac (PPC32/PPC64BE) support, see:
            #{Formatter.url("https://github.com/mistydemeo/tigerbrew")}
        EOS
      end

      sig { params(action: String).void }
      def ask_input(action: "installation")
        Homebrew::Ask.confirm?(action:)
        nil
      end

      # Compute the total sizes (download and installed) for the given formulae.
      sig { params(sized_formulae: T::Array[Formula], debug: T::Boolean).returns(T::Hash[Symbol, Integer]) }
      def compute_total_sizes(sized_formulae, debug: false)
        total_download_size  = 0
        total_installed_size = 0

        sized_formulae.each do |formula|
          bottle = formula.bottle
          next unless bottle

          # Fetch additional bottle metadata (if necessary).
          bottle.fetch_tab(quiet: !debug)

          total_download_size  += bottle.bottle_size.to_i if bottle.bottle_size
          total_installed_size += bottle.installed_size.to_i if bottle.installed_size
        end

        { download:  total_download_size,
          installed: total_installed_size }
      end

      sig {
        params(formulae_installer: T::Array[FormulaInstaller],
               dependants:         Homebrew::Upgrade::Dependents).returns(T::Array[Formula])
      }
      def collect_dependencies(formulae_installer, dependants)
        formulae_dependencies = formulae_installer.flat_map do |f|
          [f.formula, f.compute_dependencies.flatten.grep(Dependency).flat_map(&:to_formula)]
        end.flatten.uniq
        formulae_dependencies.concat(dependants.upgradeable) if dependants.upgradeable
        formulae_dependencies.uniq
      end
    end
  end
end

require "extend/os/install"
