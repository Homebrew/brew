# typed: strict
# frozen_string_literal: true

require "diagnostic"
require "diagnostic/finding"
require "fileutils"
require "hardware"
require "development_tools"
require "upgrade"
require "download_queue"
require "ask"
require "utils/output"
require "utils/topological_hash"

module Homebrew
  # Helper module for performing (pre-)install checks.
  module Install
    extend Utils::Output::Mixin

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

        opoo <<~EOS
          You passed `--cc=#{cc}`.

          #{Diagnostic::Finding.support_tier_message(tier: 3)}
        EOS
      end

      sig { params(all_fatal: T::Boolean).void }
      def perform_build_from_source_checks(all_fatal: false)
        Diagnostic.checks(:fatal_build_from_source_checks)
        Diagnostic.checks(:build_from_source_checks, fatal: all_fatal)
      end

      sig { void }
      def global_post_install; end

      sig { void }
      def check_prefix
        if (Hardware::CPU.intel? || Hardware::CPU.in_rosetta2?) &&
           HOMEBREW_PREFIX.to_s == HOMEBREW_MACOS_ARM_DEFAULT_PREFIX
          if Hardware::CPU.in_rosetta2?
            odie <<~EOS
              Cannot install under Rosetta 2 in ARM default prefix (#{HOMEBREW_PREFIX})!
              To rerun under ARM use:
                  arch -arm64 brew install ...
              To install under x86_64, install Homebrew into #{HOMEBREW_DEFAULT_PREFIX}.
            EOS
          else
            odie "Cannot install on Intel processor in ARM default prefix (#{HOMEBREW_PREFIX})!"
          end
        elsif Hardware::CPU.arm? && HOMEBREW_PREFIX.to_s == HOMEBREW_DEFAULT_PREFIX
          odie <<~EOS
            Cannot install in Homebrew on ARM processor in Intel default prefix (#{HOMEBREW_PREFIX})!
            Please create a new installation in #{HOMEBREW_MACOS_ARM_DEFAULT_PREFIX} using one of the
            "Alternative Installs" from:
              #{Formatter.url("https://docs.brew.sh/Installation")}
            You can migrate your previously installed formula list with:
              brew bundle dump
          EOS
        end
      end

      sig {
        params(formula: Formula, head: T::Boolean, fetch_head: T::Boolean,
               only_dependencies: T::Boolean, force: T::Boolean, quiet: T::Boolean,
               skip_link: T::Boolean, overwrite: T::Boolean).returns(T::Boolean)
      }
      def install_formula?(
        formula,
        head: false,
        fetch_head: false,
        only_dependencies: false,
        force: false,
        quiet: false,
        skip_link: false,
        overwrite: false
      )
        # HEAD-only without --HEAD is an error
        if !head && formula.stable.nil?
          odie <<~EOS
            #{formula.full_name} is a HEAD-only formula.
            To install it, run:
              brew install --HEAD #{formula.full_name}
          EOS
        end

        # --HEAD, fail with no head defined
        odie "No head is defined for #{formula.full_name}" if head && formula.head.nil?

        installed_head_version = formula.latest_head_version
        if installed_head_version &&
           !formula.head_version_outdated?(installed_head_version, fetch_head:)
          new_head_installed = true
        end
        prefix_installed = formula.prefix.exist? && !formula.prefix.empty?

        # Check if the installed formula is from a different tap
        if formula.any_version_installed? &&
           (current_tap_name = formula.tap&.name.presence) &&
           (installed_keg_tab = formula.any_installed_keg&.tab.presence) &&
           (installed_tap_name = installed_keg_tab.tap&.name.presence) &&
           installed_tap_name != current_tap_name
          odie <<~EOS
            #{formula.name} was installed from the #{Formatter.identifier(installed_tap_name)} tap
            but you are trying to install it from the #{Formatter.identifier(current_tap_name)} tap.
            Formulae with the same name from different taps cannot be installed at the same time.

            To install this version, you must first uninstall the existing formula:
              brew uninstall #{formula.name}
            Then you can install the desired version:
              brew install #{formula.full_name}
          EOS
        end

        if formula.keg_only? && formula.any_version_installed? && formula.optlinked? && !force
          # keg-only install is only possible when no other version is
          # linked to opt, because installing without any warnings can break
          # dependencies. Therefore before performing other checks we need to be
          # sure the --force switch is passed.
          if formula.outdated?
            if !Homebrew::EnvConfig.no_install_upgrade? && !formula.pinned?
              name = formula.name
              version = formula.linked_version
              puts "#{name} #{version} is already installed but outdated (so it will be upgraded)."
              return true
            end

            unpin_cmd_if_needed = ("brew unpin #{formula.full_name} && " if formula.pinned?)
            optlinked_version = Keg.for(formula.opt_prefix).version
            onoe <<~EOS
              #{formula.full_name} #{optlinked_version} is already installed.
              To upgrade to #{formula.version}, run:
                #{unpin_cmd_if_needed}brew upgrade #{formula.full_name}
            EOS
          elsif only_dependencies
            return true
          elsif !quiet
            opoo_without_github_actions_annotation <<~EOS
              #{formula.full_name} #{formula.pkg_version} is already installed and up-to-date.
              To reinstall #{formula.pkg_version}, run:
                brew reinstall #{formula.name}
            EOS
          end
        elsif (head && new_head_installed) || prefix_installed
          # After we're sure the --force switch was passed for linking to opt
          # keg-only we need to be sure that the version we're attempting to
          # install is not already installed.

          installed_version = if head
            formula.latest_head_version
          else
            formula.pkg_version
          end

          msg = "#{formula.full_name} #{installed_version} is already installed"
          linked_not_equals_installed = formula.linked_version != installed_version
          if formula.linked? && linked_not_equals_installed
            msg = if quiet
              nil
            else
              <<~EOS
                #{msg}.
                The currently linked version is: #{formula.linked_version}
              EOS
            end
          elsif only_dependencies || (!formula.linked? && overwrite)
            msg = nil
            return true
          elsif !formula.linked? || formula.keg_only?
            msg = <<~EOS
              #{msg}, it's just not linked.
              To link this version, run:
                brew link #{formula.full_name}
            EOS
          else
            unless quiet
              opoo_without_github_actions_annotation <<~EOS
                #{msg} and up-to-date.
                To reinstall #{formula.pkg_version}, run:
                  brew reinstall #{formula.name}
              EOS
            end
            msg = nil
          end
          opoo msg if msg
        elsif !formula.any_version_installed? && (old_formula = formula.old_installed_formulae.first)
          msg = "#{old_formula.full_name} #{old_formula.any_installed_version} already installed"
          msg = if !old_formula.linked? && !old_formula.keg_only?
            <<~EOS
              #{msg}, it's just not linked.
              To link this version, run:
                brew link #{old_formula.full_name}
            EOS
          elsif quiet
            nil
          else
            "#{msg}."
          end
          opoo msg if msg
        elsif formula.migration_needed? && !force
          # Check if the formula we try to install is the same as installed
          # but not migrated one. If --force is passed then install anyway.
          opoo <<~EOS
            #{formula.oldnames_to_migrate.first} is already installed, it's just not migrated.
            To migrate this formula, run:
              brew migrate #{formula}
            Or to force-install it, run:
              brew install #{formula} --force
          EOS
        elsif formula.linked?
          message = "#{formula.name} #{formula.linked_version} is already installed"
          if formula.outdated? && !head
            if !Homebrew::EnvConfig.no_install_upgrade? && !formula.pinned?
              puts "#{message} but outdated (so it will be upgraded)."
              return true
            end

            unpin_cmd_if_needed = ("brew unpin #{formula.full_name} && " if formula.pinned?)
            onoe <<~EOS
              #{message}
              To upgrade to #{formula.pkg_version}, run:
                #{unpin_cmd_if_needed}brew upgrade #{formula.full_name}
            EOS
          elsif only_dependencies || skip_link
            return true
          else
            onoe <<~EOS
              #{message}
              To install #{formula.pkg_version}, first run:
                brew unlink #{formula.name}
            EOS
          end
        else
          # If none of the above is true and the formula is linked, then
          # FormulaInstaller will handle this case.
          return true
        end

        # Even if we don't install this formula mark it as no longer just
        # installed as a dependency.
        return false unless formula.opt_prefix.directory?

        keg = Keg.new(formula.opt_prefix.resolved_path)
        tab = keg.tab
        unless tab.installed_on_request
          tab.installed_on_request = true
          tab.write
        end

        false
      end

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
        formulae_names_to_install = formula_installers.map { |fi| fi.formula.name }
        return formula_installers if formulae_names_to_install.empty?

        download_queue = T.let(download_queue || Homebrew::DownloadQueue.new(pour: true), Homebrew::DownloadQueue)

        if show_downloads_heading
          formula_sentence = formulae_names_to_install.map { |name| Formatter.identifier(name) }.to_sentence
          oh1 "Fetching downloads for: #{formula_sentence}", truncate: false
        end

        begin
          valid_formula_installers = prelude_fetch_formulae(formula_installers, download_queue:)
          download_queue.fetch

          [:prelude, :enqueue_fetch].each do |step|
            valid_formula_installers.select! do |fi|
              fi.public_send(step)
              true
            rescue CannotInstallFormulaError => e
              ofail e.message
              false
            rescue UnsatisfiedRequirements, DownloadError, ChecksumMismatchError => e
              ofail "#{fi.formula}: #{e}"
              false
            end
            next if step == :enqueue_fetch && !fetch_after_enqueue

            download_queue.fetch
          end
        ensure
          download_queue.shutdown if shutdown_download_queue
        end

        valid_formula_installers
      end

      sig {
        params(
          formula_installers: T::Array[FormulaInstaller],
          download_queue:     Homebrew::DownloadQueue,
        ).returns(T::Array[FormulaInstaller])
      }
      def prelude_fetch_formulae(formula_installers, download_queue:)
        formula_installers.each do |fi|
          fi.download_queue = download_queue
        end

        formula_installers.select do |fi|
          fi.prelude_fetch
          true
        rescue CannotInstallFormulaError => e
          ofail e.message
          false
        rescue UnsatisfiedRequirements, DownloadError, ChecksumMismatchError => e
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

      sig { params(formula_names: T::Array[String], cask_names: T::Array[String]).void }
      def show_combined_fetch_downloads_heading(formula_names: [], cask_names: [])
        combined_fetch_targets = formula_names.map { |name| Formatter.identifier(name) } +
                                 cask_names.map { |name| Formatter.identifier(name) }
        return if combined_fetch_targets.empty?

        oh1 "Fetching downloads for: #{combined_fetch_targets.to_sentence}", truncate: false
      end

      sig { params(cask_installers: T::Array[T.untyped], download_queue: Homebrew::DownloadQueue).void }
      def enqueue_cask_installers(cask_installers, download_queue:)
        if cask_installers.any?(&:source_download_requires_pre_fetch?)
          source_downloads = cask_installers.filter_map(&:prelude_fetch_download)
          if source_downloads.any?
            oh1 "Downloading Cask files"
            source_downloads.each { |source_download| download_queue.enqueue(source_download) }
            download_queue.fetch
          end
        end

        cask_installers.each(&:enqueue_downloads)
      end

      sig {
        params(formula_installers: T::Array[FormulaInstaller], installed_on_request: T::Boolean,
               build_bottle: T::Boolean, force_bottle: T::Boolean,
               bottle_arch: T.nilable(String), ignore_deps: T::Boolean, only_deps: T::Boolean,
               include_test_formulae: T::Array[String], build_from_source_formulae: T::Array[String],
               cc: T.nilable(String), git: T::Boolean, interactive: T::Boolean, keep_tmp: T::Boolean,
               debug_symbols: T::Boolean, force: T::Boolean, overwrite: T::Boolean, debug: T::Boolean,
               quiet: T::Boolean, verbose: T::Boolean, dry_run: T::Boolean,
               dry_run_action: String, skip_post_install: T::Boolean, skip_link: T::Boolean).void
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
        skip_link: false
      )
        formulae_names_to_install = formula_installers.map { |fi| fi.formula.name }
        return if formulae_names_to_install.empty?

        if dry_run
          ohai "Would #{dry_run_action} #{Utils.pluralize("formula", formulae_names_to_install.count,
                                                          include_count: true)}:"
          puts formulae_names_to_install.join(" ")

          formula_installers.each do |fi|
            print_dry_run_dependencies(fi.formula, fi.compute_dependencies, &:name)
          end
          return
        end

        formula_installers.each do |fi|
          formula = fi.formula
          upgrade = formula.linked? && formula.outdated? && !formula.head? && !Homebrew::EnvConfig.no_install_upgrade?
          install_formula(fi, upgrade:)
          Cleanup.install_formula_clean!(formula)
        end
      end

      sig {
        params(
          formula:            Formula,
          dependencies:       T::Array[Dependency],
          skip_formula_names: T::Array[String],
          _block:             T.proc.params(arg0: Formula).returns(String),
        ).void
      }
      def print_dry_run_dependencies(formula, dependencies, skip_formula_names: [], &_block)
        return if dependencies.empty?

        entries = dependencies.filter_map do |dep|
          dependency = dep.to_formula
          next if skip_formula_names.include?(dependency.full_name)

          [dependency.any_version_installed?, yield(dependency)]
        end

        upgrade, install = entries.partition(&:first)
        { install:, upgrade: }.each do |verb, group|
          next if group.empty?

          ohai "Would #{verb} #{Utils.pluralize("dependency", group.count, include_count: true)} " \
               "for #{formula.name}:"
          puts Upgrade.format_upgrade_summary(group.map(&:last))
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
        formulae_installer.any? { |formula_installer| formula_installer.compute_dependencies.present? } ||
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
                                                  .map { |k| Keg.new(k.resolved_path) }
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
