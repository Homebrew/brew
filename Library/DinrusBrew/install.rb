# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "diagnostic"
require "fileutils"
require "hardware"
require "development_tools"
require "upgrade"

module DinrusBrew
  # Helper module for performing (pre-)install checks.
  module Install
    class << self
      sig { params(all_fatal: T::Boolean).void }
      def perform_preinstall_checks_once(all_fatal: false)
        @perform_preinstall_checks_once ||= {}
        @perform_preinstall_checks_once[all_fatal] ||= begin
          perform_preinstall_checks(all_fatal:)
          true
        end
      end

      def check_cc_argv(cc)
        return unless cc

        @checks ||= Diagnostic::Checks.new
        opoo <<~EOS
          Передано `--cc=#{cc}`.
          #{@checks.please_create_pull_requests}
        EOS
      end

      def perform_build_from_source_checks(all_fatal: false)
        Diagnostic.checks(:fatal_build_from_source_checks)
        Diagnostic.checks(:build_from_source_checks, fatal: all_fatal)
      end

      def global_post_install; end
      alias generic_global_post_install global_post_install

      def check_prefix
        if (Hardware::CPU.intel? || Hardware::CPU.in_rosetta2?) &&
           DINRUSBREW_PREFIX.to_s == DINRUSBREW_MACOS_ARM_DEFAULT_PREFIX
          if Hardware::CPU.in_rosetta2?
            odie <<~EOS
              Cannot install under Rosetta 2 in ARM default prefix (#{DINRUSBREW_PREFIX})!
              To rerun under ARM use:
                  arch -arm64 brew install ...
              To install under x86_64, install DinrusBrew into #{DINRUSBREW_DEFAULT_PREFIX}.
            EOS
          else
            odie "Cannot install on Intel processor in ARM default prefix (#{DINRUSBREW_PREFIX})!"
          end
        elsif Hardware::CPU.arm? && DINRUSBREW_PREFIX.to_s == DINRUSBREW_DEFAULT_PREFIX
          odie <<~EOS
            Cannot install in DinrusBrew on ARM processor in Intel default prefix (#{DINRUSBREW_PREFIX})!
            Please create a new installation in #{DINRUSBREW_MACOS_ARM_DEFAULT_PREFIX} using one of the
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
        quiet: false,
        skip_link: false,
        overwrite: false
      )
        # head-only without --HEAD is an error
        if !head && formula.stable.nil?
          odie <<~EOS
            #{formula.full_name} это формула head-only.
            Для её установки выполните:
              brew install --HEAD #{formula.full_name}
          EOS
        end

        # --HEAD, fail with no head defined
        odie "Не определён head для #{formula.full_name}" if head && formula.head.nil?

        installed_head_version = formula.latest_head_version
        if installed_head_version &&
           !formula.head_version_outdated?(installed_head_version, fetch_head:)
          new_head_installed = true
        end
        prefix_installed = formula.prefix.exist? && !formula.prefix.children.empty?

        if formula.keg_only? && formula.any_version_installed? && formula.optlinked? && !force
          # keg-only install is only possible when no other version is
          # linked to opt, because installing without any warnings can break
          # dependencies. Therefore before performing other checks we need to be
          # sure the --force switch is passed.
          if formula.outdated?
            if !DinrusBrew::EnvConfig.no_install_upgrade? && !formula.pinned?
              name = formula.name
              version = formula.linked_version
              puts "#{name} #{version} уже установлен, но устарел (его ждёт апгрейд)."
              return true
            end

            unpin_cmd_if_needed = ("brew unpin #{formula.full_name} && " if formula.pinned?)
            optlinked_version = Keg.for(formula.opt_prefix).version
            onoe <<~EOS
              #{formula.full_name} #{optlinked_version} уже установлен.
              Для апгрейда до #{formula.version} выполните:
                #{unpin_cmd_if_needed}brew upgrade #{formula.full_name}
            EOS
          elsif only_dependencies
            return true
          elsif !quiet
            opoo <<~EOS
              #{formula.full_name} #{formula.pkg_version} уже установлен и свеж.
              Для переустановки #{formula.pkg_version} выполните:
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

          msg = "#{formula.full_name} #{installed_version} уже установлен"
          linked_not_equals_installed = formula.linked_version != installed_version
          if formula.linked? && linked_not_equals_installed
            msg = if quiet
              nil
            else
              <<~EOS
                #{msg}.
                Текущая линкованная версия: #{formula.linked_version}
              EOS
            end
          elsif only_dependencies || (!formula.linked? && overwrite)
            msg = nil
            return true
          elsif !formula.linked? || formula.keg_only?
            msg = <<~EOS
              #{msg}, он просто не линкован.
              Для линковки этой версии выполните:
                brew link #{formula}
            EOS
          else
            msg = if quiet
              nil
            else
              <<~EOS
                #{msg} и свеж.
                Для переустановки #{formula.pkg_version} выполните:
                  brew reinstall #{formula.name}
              EOS
            end
          end
          opoo msg if msg
        elsif !formula.any_version_installed? && (old_formula = formula.old_installed_formulae.first)
          msg = "#{old_formula.full_name} #{old_formula.any_installed_version} already installed"
          msg = if !old_formula.linked? && !old_formula.keg_only?
            <<~EOS
              #{msg}, он просто не линкован.
              Для линковки этой версии выполните:
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
            #{formula.oldnames_to_migrate.first} уже установлен, но не мигрирован.
            Чтобы мигрировать эту формулу, выполните:
              brew migrate #{formula}
            Или установить её принудительно, выполните:
              brew install #{formula} --force
          EOS
        elsif formula.linked?
          message = "#{formula.name} #{formula.linked_version} уже установлен"
          if formula.outdated? && !head
            if !DinrusBrew::EnvConfig.no_install_upgrade? && !formula.pinned?
              puts "#{message}, но устарел (поэтому ожидает апгрейда)."
              return true
            end

            unpin_cmd_if_needed = ("brew unpin #{formula.full_name} && " if formula.pinned?)
            onoe <<~EOS
              #{message}
              Для апгрейда до #{formula.pkg_version} выполните:
                #{unpin_cmd_if_needed}brew upgrade #{formula.full_name}
            EOS
          elsif only_dependencies || skip_link
            return true
          else
            onoe <<~EOS
              #{message}
              Чтобы установить #{formula.pkg_version}, вначале выполните:
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
        skip_post_install: false,
        skip_link: false
      )
        formula_installers = formulae_to_install.filter_map do |formula|
          Migrator.migrate_if_needed(formula, force:, dry_run:)
          build_options = formula.build

          formula_installer = FormulaInstaller.new(
            formula,
            options:                    build_options.used_options,
            installed_on_request:       true,
            installed_as_dependency:    false,
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
        end

        if dry_run
          if (formulae_name_to_install = formulae_to_install.map(&:name))
            ohai "Был бы установлен #{Utils.pluralize("formula", formulae_name_to_install.count,
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

        ohai "Был бы установлен #{Utils.pluralize("dependenc", dependencies.count, plural: "ies", singular: "y",
                                            include_count: true)} for #{formula.name}:"
        formula_names = dependencies.map { |(dep, _options)| yield dep.to_formula }
        puts formula_names.join(" ")
      end

      private

      def perform_preinstall_checks(all_fatal: false)
        check_prefix
        check_cpu
        attempt_directory_creation
        Diagnostic.checks(:supported_configuration_checks, fatal: all_fatal)
        Diagnostic.checks(:fatal_preinstall_checks)
      end
      alias generic_perform_preinstall_checks perform_preinstall_checks

      def attempt_directory_creation
        Keg.must_exist_directories.each do |dir|
          FileUtils.mkdir_p(dir) unless dir.exist?
        rescue
          nil
        end
      end

      def check_cpu
        return unless Hardware::CPU.ppc?

        odie <<~EOS
          Sorry, DinrusBrew does not support your computer's CPU architecture!
          For PowerPC Mac (PPC32/PPC64BE) support, see:
            #{Formatter.url("https://github.com/mistydemeo/tigerbrew")}
        EOS
      end

      def install_formula(formula_installer)
        formula = formula_installer.formula

        upgrade = formula.linked? && formula.outdated? && !formula.head? && !DinrusBrew::EnvConfig.no_install_upgrade?

        Upgrade.install_formula(formula_installer, upgrade:)
      end
    end
  end
end

require "extend/os/install"
