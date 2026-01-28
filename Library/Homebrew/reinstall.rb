# typed: strict
# frozen_string_literal: true

require "development_tools"
require "messages"
require "utils/output"

# Needed to handle circular require dependency.
# rubocop:disable Lint/EmptyClass
class FormulaInstaller; end
# rubocop:enable Lint/EmptyClass

module Homebrew
  module Reinstall
    extend Utils::Output::Mixin

    class InstallationContext < T::Struct
      const :formula_installer, ::FormulaInstaller
      const :keg, T.nilable(Keg)
      const :formula, Formula
      const :options, Options
    end

    class << self
      sig {
        params(
          formula: Formula, flags: T::Array[String], force_bottle: T::Boolean,
          build_from_source_formulae: T::Array[String], interactive: T::Boolean, keep_tmp: T::Boolean,
          debug_symbols: T::Boolean, force: T::Boolean, debug: T::Boolean, quiet: T::Boolean,
          verbose: T::Boolean, git: T::Boolean
        ).returns(InstallationContext)
      }
      def build_install_context(
        formula,
        flags:,
        force_bottle: false,
        build_from_source_formulae: [],
        interactive: false,
        keep_tmp: false,
        debug_symbols: false,
        force: false,
        debug: false,
        quiet: false,
        verbose: false,
        git: false
      )
        if formula.opt_prefix.directory?
          keg = Keg.new(formula.opt_prefix.resolved_path)
          tab = keg.tab
          link_keg = keg.linked?
          installed_as_dependency = tab.installed_as_dependency == true
          installed_on_request = tab.installed_on_request == true
          build_bottle = tab.built_bottle?
          backup keg
        else
          link_keg = nil
          installed_as_dependency = false
          installed_on_request = true
          build_bottle = false
        end

        build_options = BuildOptions.new(Options.create(flags), formula.options)
        options = build_options.used_options
        options |= formula.build.used_options
        options &= formula.options

        formula_installer = FormulaInstaller.new(
          formula,
          **{
            options:,
            link_keg:,
            installed_as_dependency:,
            installed_on_request:,
            build_bottle:,
            force_bottle:,
            build_from_source_formulae:,
            git:,
            interactive:,
            keep_tmp:,
            debug_symbols:,
            force:,
            debug:,
            quiet:,
            verbose:,
          }.compact,
        )
        InstallationContext.new(formula_installer:, keg:, formula:, options:)
      end

      sig { params(install_context: InstallationContext).void }
      def reinstall_formula(install_context)
        formula_installer = install_context.formula_installer
        keg = install_context.keg
        formula = install_context.formula
        options = install_context.options
        link_keg = keg&.linked?
        verbose = formula_installer.verbose?

        oh1 "Reinstalling #{Formatter.identifier(formula.full_name)} #{options.to_a.join " "}"

        formula_installer.install
        formula_installer.finish
      rescue FormulaInstallationAlreadyAttemptedError
        nil
        # Any other exceptions we want to restore the previous keg and report the error.
      rescue Exception # rubocop:disable Lint/RescueException
        ignore_interrupts { restore_backup(keg, link_keg, verbose:) if keg }
        raise
      else
        if keg
          backup_keg = backup_path(keg)
          begin
            FileUtils.rm_r(backup_keg) if backup_keg.exist?
          rescue Errno::EACCES, Errno::ENOTEMPTY
            odie <<~EOS
              Could not remove #{backup_keg.parent.basename} backup keg! Do so manually:
                sudo rm -rf #{backup_keg}
            EOS
          end
        end
      end

      sig { params(dry_run: T::Boolean).void }
      def reinstall_pkgconf_if_needed!(dry_run: false)
        nil
      end

      private

      sig { params(keg: Keg).void }
      def backup(keg)
        keg.unlink
        begin
          keg.rename backup_path(keg)
        rescue Errno::EACCES, Errno::ENOTEMPTY
          odie <<~EOS
            Could not rename #{keg.name} keg! Check/fix its permissions:
              sudo chown -R #{ENV.fetch("USER", "$(whoami)")} #{keg}
          EOS
        end
      end

      sig { params(keg: Keg, keg_was_linked: T::Boolean, verbose: T::Boolean).void }
      def restore_backup(keg, keg_was_linked, verbose:)
        path = backup_path(keg)

        return unless path.directory?

        FileUtils.rm_r(Pathname.new(keg)) if keg.exist?

        path.rename keg.to_s
        keg.link(verbose:) if keg_was_linked
      end

      sig { params(keg: Keg).returns(Pathname) }
      def backup_path(keg)
        Pathname.new "#{keg}.reinstall"
      end
    end
  end
end

require "extend/os/reinstall"
