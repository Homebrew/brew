# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "formula_installer"
require "development_tools"
require "messages"

module Homebrew
  module Reinstall
    def self.reinstall_formula(
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

      fi = FormulaInstaller.new(
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
      fi.prelude
      fi.fetch

      oh1 "Reinstalling #{Formatter.identifier(formula.full_name)} #{options.to_a.join " "}"

      fi.install
      fi.finish
    rescue FormulaInstallationAlreadyAttemptedError
      nil
    # Any other exceptions we want to restore the previous keg and report the error.
    rescue Exception # rubocop:disable Lint/RescueException
      ignore_interrupts { restore_backup(keg, link_keg, verbose:) }
      raise
    else
      begin
        FileUtils.rm_r(backup_path(keg)) if backup_path(keg).exist?
      rescue Errno::EACCES, Errno::ENOTEMPTY
        odie <<~EOS
          Could not remove #{backup_path(keg).parent.basename} backup keg! Do so manually:
            sudo rm -rf #{backup_path(keg)}
        EOS
      end
    end

    def self.backup(keg)
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
    private_class_method :backup

    def self.restore_backup(keg, keg_was_linked, verbose:)
      path = backup_path(keg)

      return unless path.directory?

      FileUtils.rm_r(Pathname.new(keg)) if keg.exist?

      path.rename keg
      keg.link(verbose:) if keg_was_linked
    end
    private_class_method :restore_backup

    def self.backup_path(path)
      Pathname.new "#{path}.reinstall"
    end
    private_class_method :backup_path
  end
end
