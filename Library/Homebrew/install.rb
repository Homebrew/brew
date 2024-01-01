# typed: true
# frozen_string_literal: true

require "diagnostic"
require "fileutils"
require "hardware"
require "development_tools"
require "upgrade"

module Homebrew
  # Helper module for performing (pre-)install checks.
  #
  # @api private
  module Install
    class << self
      def perform_preinstall_checks(all_fatal: false, cc: nil)
        check_prefix
        check_cpu
        attempt_directory_creation
        check_cc_argv(cc)
        Diagnostic.checks(:supported_configuration_checks, fatal: all_fatal)
        Diagnostic.checks(:fatal_preinstall_checks)
      end
      alias generic_perform_preinstall_checks perform_preinstall_checks

      def perform_build_from_source_checks(all_fatal: false)
        Diagnostic.checks(:fatal_build_from_source_checks)
        Diagnostic.checks(:build_from_source_checks, fatal: all_fatal)
      end

      def global_post_install; end
      alias generic_global_post_install global_post_install

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

      def install_formula?(
        formula,
        head: false,
        fetch_head: false,
        only_dependencies: false,
        force: false,
        quiet: false
      )
        # head-only without --HEAD is an error
        if !head && formula.stable.nil?
          odie <<~EOS
            #{formula.full_name} is a head-only formula.
            To install it, run:
              brew install --HEAD #{formula.full_name}
          EOS
        end

        # --HEAD, fail with no head defined
        odie "No head is defined for #{formula.full_name}" if head && formula.head.nil?

        installed_head_version = formula.latest_head_version
        if installed_head_version &&
           !formula.head_version_outdated?(installed_head_version, fetch_head: fetch_head)
          new_head_installed = true
        end
        prefix_installed = formula.prefix.exist? && !formula.prefix.children.empty?

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
          elsif only_dependencies
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
          elsif only_dependencies
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
        tab = Tab.for_keg(keg)
        unless tab.installed_on_request
          tab.installed_on_request = true
          tab.write
        end

        false
      end

      def install_formulae(
        formulae_to_install,
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
        skip_post_install: false
      )
        formula_installers = formulae_to_install.map do |formula|
          Migrator.migrate_if_needed(formula, force: force, dry_run: dry_run)
          build_options = formula.build

          formula_installer = FormulaInstaller.new(
            formula,
            options:                    build_options.used_options,
            build_bottle:               build_bottle,
            force_bottle:               force_bottle,
            bottle_arch:                bottle_arch,
            ignore_deps:                ignore_deps,
            only_deps:                  only_deps,
            include_test_formulae:      include_test_formulae,
            build_from_source_formulae: build_from_source_formulae,
            cc:                         cc,
            git:                        git,
            interactive:                interactive,
            keep_tmp:                   keep_tmp,
            debug_symbols:              debug_symbols,
            force:                      force,
            overwrite:                  overwrite,
            debug:                      debug,
            quiet:                      quiet,
            verbose:                    verbose,
            skip_post_install:          skip_post_install,
          )

          begin
            unless dry_run
              formula_installer.prelude
              formula_installer.fetch
            end
            formula_installer
          rescue CannotInstallFormulaError => e
            ofail e.message
            nil
          rescue UnsatisfiedRequirements, DownloadError, ChecksumMismatchError => e
            ofail "#{formula}: #{e}"
            nil
          end
        end.compact

        if dry_run
          if (formulae_name_to_install = formulae_to_install.map(&:name))
            ohai "Would install #{Utils.pluralize("formula", formulae_name_to_install.count,
                                                  plural: "e", include_count: true)}:"
            puts formulae_name_to_install.join(" ")

            formula_installers.each do |fi|
              print_dry_run_dependencies(fi.formula, fi.compute_dependencies, &:name)
            end
          end
          return
        end

        formula_installers.each do |fi|
          install_formula(fi)
          Cleanup.install_formula_clean!(fi.formula)
        end
      end

      def print_dry_run_dependencies(formula, dependencies)
        return if dependencies.empty?

        ohai "Would install #{Utils.pluralize("dependenc", dependencies.count, plural: "ies", singular: "y",
                                            include_count: true)} for #{formula.name}:"
        formula_names = dependencies.map { |(dep, _options)| yield dep.to_formula }
        puts formula_names.join(" ")
      end

      private

      def check_cc_argv(cc)
        return unless cc

        @checks ||= Diagnostic::Checks.new
        opoo <<~EOS
          You passed `--cc=#{cc}`.
          #{@checks.please_create_pull_requests}
        EOS
      end

      def attempt_directory_creation
        Keg::MUST_EXIST_DIRECTORIES.each do |dir|
          FileUtils.mkdir_p(dir) unless dir.exist?

          # Create these files to ensure that these directories aren't removed
          # by the Catalina installer.
          # (https://github.com/Homebrew/brew/issues/6263)
          keep_file = dir/".keepme"
          FileUtils.touch(keep_file) unless keep_file.exist?
        rescue
          nil
        end
      end

      def check_cpu
        return unless Hardware::CPU.ppc?

        odie <<~EOS
          Sorry, Homebrew does not support your computer's CPU architecture!
          For PowerPC Mac (PPC32/PPC64BE) support, see:
            #{Formatter.url("https://github.com/mistydemeo/tigerbrew")}
        EOS
      end

      def install_formula(formula_installer)
        formula = formula_installer.formula

        upgrade = formula.linked? && formula.outdated? && !formula.head? && !Homebrew::EnvConfig.no_install_upgrade?

        Upgrade.install_formula(formula_installer, upgrade: upgrade)
      end
    end
  end
end

require "extend/os/install"
