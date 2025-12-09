# typed: strict
# frozen_string_literal: true

require "diagnostic"
require "fileutils"
require "hardware"
require "development_tools"
require "upgrade"
require "download_queue"
require "utils/output"

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

        @checks ||= T.let(Diagnostic::Checks.new, T.nilable(Homebrew::Diagnostic::Checks))
        opoo <<~EOS
          You passed `--cc=#{cc}`.

          #{@checks.support_tier_message(tier: 3)}
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
        prefix_installed = formula.prefix.exist? && !formula.prefix.children.empty?

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
            opoo <<~EOS
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
                brew link #{formula}
            EOS
          else
            msg = if quiet
              nil
            else
              <<~EOS
                #{msg} and up-to-date.
                To reinstall #{formula.pkg_version}, run:
                  brew reinstall #{formula.name}
              EOS
            end
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
               installed_as_dependency: T::Boolean, build_bottle: T::Boolean, force_bottle: T::Boolean,
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
        installed_as_dependency: false,
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
            installed_as_dependency:,
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

      sig { params(formula_installers: T::Array[FormulaInstaller]).returns(T::Array[FormulaInstaller]) }
      def fetch_formulae(formula_installers)
        formulae_names_to_install = formula_installers.map { |fi| fi.formula.name }
        return formula_installers if formulae_names_to_install.empty?

        formula_sentence = formulae_names_to_install.map { |name| Formatter.identifier(name) }.to_sentence
        oh1 "Fetching downloads for: #{formula_sentence}", truncate: false
        if EnvConfig.download_concurrency > 1
          download_queue = Homebrew::DownloadQueue.new(pour: true)
          formula_installers.each do |fi|
            fi.download_queue = download_queue
          end
        end

        valid_formula_installers = formula_installers.dup

        begin
          [:prelude_fetch, :prelude, :fetch].each do |step|
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
            download_queue&.fetch
          end
        ensure
          download_queue&.shutdown
        end

        valid_formula_installers
      end

      sig {
        params(formula_installers: T::Array[FormulaInstaller], installed_on_request: T::Boolean,
               installed_as_dependency: T::Boolean, build_bottle: T::Boolean, force_bottle: T::Boolean,
               bottle_arch: T.nilable(String), ignore_deps: T::Boolean, only_deps: T::Boolean,
               include_test_formulae: T::Array[String], build_from_source_formulae: T::Array[String],
               cc: T.nilable(String), git: T::Boolean, interactive: T::Boolean, keep_tmp: T::Boolean,
               debug_symbols: T::Boolean, force: T::Boolean, overwrite: T::Boolean, debug: T::Boolean,
               quiet: T::Boolean, verbose: T::Boolean, dry_run: T::Boolean,
               skip_post_install: T::Boolean, skip_link: T::Boolean).void
      }
      def install_formulae(
        formula_installers,
        installed_on_request: true,
        installed_as_dependency: false,
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
        formulae_names_to_install = formula_installers.map { |fi| fi.formula.name }
        return if formulae_names_to_install.empty?

        if dry_run
          ohai "Would install #{Utils.pluralize("formula", formulae_names_to_install.count, include_count: true)}:"
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
          formula:      Formula,
          dependencies: T::Array[Dependency],
          _block:       T.proc.params(arg0: Formula).returns(String),
        ).void
      }
      def print_dry_run_dependencies(formula, dependencies, &_block)
        return if dependencies.empty?

        ohai "Would install #{Utils.pluralize("dependency", dependencies.count, include_count: true)} " \
             "for #{formula.name}:"
        formula_names = dependencies.map { |dep| yield dep.to_formula }
        puts formula_names.join(" ")
      end

      # If asking the user is enabled, show dependency and size information.
      sig { params(formulae_installer: T::Array[FormulaInstaller], dependants: Homebrew::Upgrade::Dependents, args: Homebrew::CLI::Args).void }
      def ask_formulae(formulae_installer, dependants, args:)
        return if formulae_installer.empty?

        formulae = collect_dependencies(formulae_installer, dependants)

        ohai "Looking for bottles..."

        sizes = compute_total_sizes(formulae, debug: args.debug?)

        puts "#{::Utils.pluralize("Formula", formulae.count)} \
(#{formulae.count}): #{formulae.join(", ")}\n\n"
        puts "Download Size: #{disk_usage_readable(sizes.fetch(:download))}"
        puts "Install Size:  #{disk_usage_readable(sizes.fetch(:installed))}"
        if (net_install_size = sizes[:net]) && net_install_size != 0
          puts "Net Install Size: #{disk_usage_readable(net_install_size)}"
        end

        ask_input
      end

      sig { params(casks: T::Array[Cask::Cask]).void }
      def ask_casks(casks)
        return if casks.empty?

        puts "#{::Utils.pluralize("Cask", casks.count, plural: "s")} \
(#{casks.count}): #{casks.join(", ")}\n\n"

        ask_input
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

      private

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

      sig { void }
      def ask_input
        ohai "Do you want to proceed with the installation? [Y/y/yes/N/n/no]"
        accepted_inputs = %w[y yes]
        declined_inputs = %w[n no]
        loop do
          result = $stdin.gets
          return unless result

          result = result.chomp.strip.downcase
          if accepted_inputs.include?(result)
            break
          elsif declined_inputs.include?(result)
            exit 1
          else
            puts "Invalid input. Please enter 'Y', 'y', or 'yes' to proceed, or 'N' to abort."
          end
        end
      end

      # Compute the total sizes (download, installed, and net) for the given formulae.
      sig { params(sized_formulae: T::Array[Formula], debug: T::Boolean).returns(T::Hash[Symbol, Integer]) }
      def compute_total_sizes(sized_formulae, debug: false)
        total_download_size  = 0
        total_installed_size = 0
        total_net_size       = 0

        sized_formulae.each do |formula|
          bottle = formula.bottle
          next unless bottle

          # Fetch additional bottle metadata (if necessary).
          bottle.fetch_tab(quiet: !debug)

          total_download_size  += bottle.bottle_size.to_i if bottle.bottle_size
          total_installed_size += bottle.installed_size.to_i if bottle.installed_size

          # Sum disk usage for all installed kegs of the formula.
          next if formula.installed_kegs.none?

          kegs_dep_size = formula.installed_kegs.sum { |keg| keg.disk_usage.to_i }
          total_net_size += bottle.installed_size.to_i - kegs_dep_size if bottle.installed_size
        end

        { download:  total_download_size,
          installed: total_installed_size,
          net:       total_net_size }
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
