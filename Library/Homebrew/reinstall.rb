# typed: true
# frozen_string_literal: true

require "formula_installer"
require "development_tools"
require "messages"

module Homebrew
  module_function

  def reinstall_formula(
    formula,
    flags:,
    installed_on_request: false,
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
      tab = Tab.for_keg(keg)
      keg_had_linked_opt = true
      keg_was_linked = keg.linked?
      backup keg
    end

    build_options = BuildOptions.new(Options.create(flags), formula.options)
    options = build_options.used_options
    options |= formula.build.used_options
    options &= formula.options

    fi = FormulaInstaller.new(
      formula,
      **{
        options:                    options,
        link_keg:                   keg_had_linked_opt ? keg_was_linked : nil,
        installed_as_dependency:    tab&.installed_as_dependency,
        installed_on_request:       installed_on_request || tab&.installed_on_request,
        build_bottle:               tab&.built_bottle?,
        force_bottle:               force_bottle,
        build_from_source_formulae: build_from_source_formulae,
        git:                        git,
        interactive:                interactive,
        keep_tmp:                   keep_tmp,
        debug_symbols:              debug_symbols,
        force:                      force,
        debug:                      debug,
        quiet:                      quiet,
        verbose:                    verbose,
      }.compact,
    )
    fi.prelude
    fi.fetch

    oh1 "Reinstalling #{Formatter.identifier(formula.full_name)} #{options.to_a.join " "}"

    fi.install
    fi.finish
  rescue FormulaInstallationAlreadyAttemptedError
    nil
  rescue Exception # rubocop:disable Lint/RescueException
    ignore_interrupts { restore_backup(keg, keg_was_linked, verbose: verbose) }
    raise
  else
    begin
      backup_path(keg).rmtree if backup_path(keg).exist?
    rescue Errno::EACCES, Errno::ENOTEMPTY
      odie <<~EOS
        Could not remove #{backup_path(keg).parent.basename} backup keg! Do so manually:
          sudo rm -rf #{backup_path(keg)}
      EOS
    end
  end

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

  def restore_backup(keg, keg_was_linked, verbose:)
    path = backup_path(keg)

    return unless path.directory?

    Pathname.new(keg).rmtree if keg.exist?

    path.rename keg
    keg.link(verbose: verbose) if keg_was_linked
  end

  def backup_path(path)
    Pathname.new "#{path}.reinstall"
  end
end
