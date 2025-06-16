# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "reinstall"
require "formula_installer"
require "development_tools"
require "messages"
require "cleanup"
require "utils/topological_hash"

module Homebrew
  # Helper functions for upgrading formulae.
  module Upgrade
    def self.upgrade_formulae(
      formulae_to_install,
      flags:,
      dry_run: false,
      force_bottle: false,
      build_from_source_formulae: [],
      dependents: false,
      interactive: false,
      keep_tmp: false,
      debug_symbols: false,
      force: false,
      overwrite: false,
      debug: false,
      quiet: false,
      verbose: false
    )
      return if formulae_to_install.empty?

      # Sort keg-only before non-keg-only formulae to avoid any needless conflicts
      # with outdated, non-keg-only versions of formulae being upgraded.
      formulae_to_install.sort! do |a, b|
        if !a.keg_only? && b.keg_only?
          1
        elsif a.keg_only? && !b.keg_only?
          -1
        else
          0
        end
      end

      dependency_graph = Utils::TopologicalHash.graph_package_dependencies(formulae_to_install)
      begin
        formulae_to_install = dependency_graph.tsort & formulae_to_install
      rescue TSort::Cyclic
        raise CyclicDependencyError, dependency_graph.strongly_connected_components if Homebrew::EnvConfig.developer?
      end

      formula_installers = formulae_to_install.filter_map do |formula|
        Migrator.migrate_if_needed(formula, force:, dry_run:)
        begin
          fi = create_formula_installer(
            formula,
            flags:,
            force_bottle:,
            build_from_source_formulae:,
            interactive:,
            keep_tmp:,
            debug_symbols:,
            force:,
            overwrite:,
            debug:,
            quiet:,
            verbose:,
          )
          unless dry_run
            fi.prelude

            # Don't need to install this bottle if all of the runtime
            # dependencies have the same or newer version already installed.
            next if dependents && fi.bottle_tab_runtime_dependencies.presence&.all? do |dependency, hash|
              minimum_version = Version.new(hash["version"]) if hash["version"].present?
              Dependency.new(dependency).installed?(minimum_version:, minimum_revision: hash["revision"])
            end

            fi.fetch
          end
          fi
        rescue CannotInstallFormulaError => e
          ofail e
          nil
        rescue UnsatisfiedRequirements, DownloadError => e
          ofail "#{formula}: #{e}"
          nil
        end
      end

      formula_installers.each do |fi|
        upgrade_formula(fi, dry_run:, verbose:)
        Cleanup.install_formula_clean!(fi.formula, dry_run:)
      end
    end

    private_class_method def self.outdated_kegs(formula)
      [formula, *formula.old_installed_formulae].map(&:linked_keg)
                                                .select(&:directory?)
                                                .map { |k| Keg.new(k.resolved_path) }
    end

    private_class_method def self.print_upgrade_message(formula, fi_options)
      version_upgrade = if formula.optlinked?
        "#{Keg.new(formula.opt_prefix).version} -> #{formula.pkg_version}"
      else
        "-> #{formula.pkg_version}"
      end
      oh1 "Upgrading #{Formatter.identifier(formula.full_specified_name)}"
      puts "  #{version_upgrade} #{fi_options.to_a.join(" ")}"
    end

    private_class_method def self.create_formula_installer(
      formula,
      flags:,
      force_bottle: false,
      build_from_source_formulae: [],
      interactive: false,
      keep_tmp: false,
      debug_symbols: false,
      force: false,
      overwrite: false,
      debug: false,
      quiet: false,
      verbose: false
    )
      keg = if formula.optlinked?
        Keg.new(formula.opt_prefix.resolved_path)
      else
        formula.installed_kegs.find(&:optlinked?)
      end

      if keg
        tab = keg.tab
        link_keg = keg.linked?
        installed_as_dependency = tab.installed_as_dependency == true
        installed_on_request = tab.installed_on_request == true
        build_bottle = tab.built_bottle?
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

      FormulaInstaller.new(
        formula,
        **{
          options:,
          link_keg:,
          installed_as_dependency:,
          installed_on_request:,
          build_bottle:,
          force_bottle:,
          build_from_source_formulae:,
          interactive:,
          keep_tmp:,
          debug_symbols:,
          force:,
          overwrite:,
          debug:,
          quiet:,
          verbose:,
        }.compact,
      )
    end

    def self.upgrade_formula(formula_installer, dry_run: false, verbose: false)
      formula = formula_installer.formula

      if dry_run
        Install.print_dry_run_dependencies(formula, formula_installer.compute_dependencies) do |f|
          name = f.full_specified_name
          if f.optlinked?
            "#{name} #{Keg.new(f.opt_prefix).version} -> #{f.pkg_version}"
          else
            "#{name} #{f.pkg_version}"
          end
        end
        return
      end

      install_formula(formula_installer, upgrade: true)
    rescue BuildError => e
      e.dump(verbose:)
      puts
      Homebrew.failed = true
    end

    def self.install_formula(formula_installer, upgrade:)
      formula = formula_installer.formula

      formula_installer.check_installation_already_attempted

      if upgrade
        print_upgrade_message(formula, formula_installer.options)

        kegs = outdated_kegs(formula)
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
        linked_kegs&.each(&:link) unless formula.latest_version_installed?
      rescue
        nil
      end
    end

    private_class_method def self.check_broken_dependents(installed_formulae)
      CacheStoreDatabase.use(:linkage) do |db|
        installed_formulae.flat_map(&:runtime_installed_formula_dependents)
                          .uniq
                          .select do |f|
          keg = f.any_installed_keg
          next unless keg
          next unless keg.directory?

          LinkageChecker.new(keg, cache_db: db)
                        .broken_library_linkage?
        end.compact
      end
    end

    def self.puts_no_installed_dependents_check_disable_message_if_not_already!
      return if Homebrew::EnvConfig.no_env_hints?
      return if Homebrew::EnvConfig.no_installed_dependents_check?
      return if @puts_no_installed_dependents_check_disable_message_if_not_already

      puts "Disable this behaviour by setting HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK."
      puts "Hide these hints with HOMEBREW_NO_ENV_HINTS (see `man brew`)."
      @puts_no_installed_dependents_check_disable_message_if_not_already = true
    end

    def self.check_installed_dependents(
      formulae,
      flags:,
      dry_run: false,
      installed_on_request: false,
      force_bottle: false,
      build_from_source_formulae: [],
      interactive: false,
      keep_tmp: false,
      debug_symbols: false,
      force: false,
      debug: false,
      quiet: false,
      verbose: false
    )
      if Homebrew::EnvConfig.no_installed_dependents_check?
        unless Homebrew::EnvConfig.no_env_hints?
          opoo <<~EOS
            HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK is set: not checking for outdated
            dependents or dependents with broken linkage!
          EOS
        end
        return
      end

      installed_formulae = (dry_run ? formulae : FormulaInstaller.installed.to_a).dup
      installed_formulae.reject! { |f| f.core_formula? && f.versioned_formula? }
      return if installed_formulae.empty?

      already_broken_dependents = check_broken_dependents(installed_formulae)

      # TODO: this should be refactored to use FormulaInstaller new logic
      outdated_dependents =
        installed_formulae.flat_map(&:runtime_installed_formula_dependents)
                          .uniq
                          .select(&:outdated?)

      # Ensure we never attempt a source build for outdated dependents of upgraded formulae.
      outdated_dependents, skipped_dependents = outdated_dependents.partition do |dependent|
        dependent.bottled? && dependent.deps.map(&:to_formula).all?(&:bottled?)
      end

      if skipped_dependents.present?
        opoo <<~EOS
          The following dependents of upgraded formulae are outdated but will not
          be upgraded because they are not bottled:
            #{skipped_dependents * "\n  "}
        EOS
      end

      return if outdated_dependents.blank? && already_broken_dependents.blank?

      outdated_dependents -= installed_formulae if dry_run

      upgradeable_dependents =
        outdated_dependents.reject(&:pinned?)
                           .sort { |a, b| depends_on(a, b) }
      pinned_dependents =
        outdated_dependents.select(&:pinned?)
                           .sort { |a, b| depends_on(a, b) }

      if pinned_dependents.present?
        plural = Utils.pluralize("dependent", pinned_dependents.count)
        opoo "Not upgrading #{pinned_dependents.count} pinned #{plural}:"
        puts(pinned_dependents.map do |f|
          "#{f.full_specified_name} #{f.pkg_version}"
        end.join(", "))
      end

      # Print the upgradable dependents.
      if upgradeable_dependents.blank?
        ohai "No outdated dependents to upgrade!" unless dry_run
      else
        formula_plural = Utils.pluralize("formula", installed_formulae.count, plural: "e")
        upgrade_verb = dry_run ? "Would upgrade" : "Upgrading"
        ohai "#{upgrade_verb} #{Utils.pluralize("dependent", upgradeable_dependents.count,
                                                include_count: true)} of upgraded #{formula_plural}:"
        Upgrade.puts_no_installed_dependents_check_disable_message_if_not_already!
        formulae_upgrades = upgradeable_dependents.map do |f|
          name = f.full_specified_name
          if f.optlinked?
            "#{name} #{Keg.new(f.opt_prefix).version} -> #{f.pkg_version}"
          else
            "#{name} #{f.pkg_version}"
          end
        end
        puts formulae_upgrades.join(", ")
      end

      unless dry_run
        upgrade_formulae(
          upgradeable_dependents,
          flags:,
          force_bottle:,
          build_from_source_formulae:,
          dependents:                 true,
          interactive:,
          keep_tmp:,
          debug_symbols:,
          force:,
          debug:,
          quiet:,
          verbose:,
        )
      end

      # Update installed formulae after upgrading
      installed_formulae = FormulaInstaller.installed.to_a

      # Assess the dependents tree again now we've upgraded.
      unless dry_run
        oh1 "Checking for dependents of upgraded formulae..."
        Upgrade.puts_no_installed_dependents_check_disable_message_if_not_already!
      end

      broken_dependents = check_broken_dependents(installed_formulae)
      if broken_dependents.blank?
        if dry_run
          ohai "No currently broken dependents found!"
          opoo "If they are broken by the upgrade they will also be upgraded or reinstalled."
        else
          ohai "No broken dependents found!"
        end
        return
      end

      reinstallable_broken_dependents =
        broken_dependents.reject(&:outdated?)
                         .reject(&:pinned?)
                         .sort { |a, b| depends_on(a, b) }
      outdated_pinned_broken_dependents =
        broken_dependents.select(&:outdated?)
                         .select(&:pinned?)
                         .sort { |a, b| depends_on(a, b) }

      # Print the pinned dependents.
      if outdated_pinned_broken_dependents.present?
        count = outdated_pinned_broken_dependents.count
        plural = Utils.pluralize("dependent", outdated_pinned_broken_dependents.count)
        onoe "Not reinstalling #{count} broken and outdated, but pinned #{plural}:"
        $stderr.puts(outdated_pinned_broken_dependents.map do |f|
          "#{f.full_specified_name} #{f.pkg_version}"
        end.join(", "))
      end

      # Print the broken dependents.
      if reinstallable_broken_dependents.blank?
        ohai "No broken dependents to reinstall!"
      else
        ohai "Reinstalling #{Utils.pluralize("dependent", reinstallable_broken_dependents.count,
                                             include_count: true)} with broken linkage from source:"
        Upgrade.puts_no_installed_dependents_check_disable_message_if_not_already!
        puts reinstallable_broken_dependents.map(&:full_specified_name)
                                            .join(", ")
      end

      return if dry_run

      reinstallable_broken_dependents.each do |formula|
        Reinstall.reinstall_formula(
          formula,
          flags:,
          force_bottle:,
          build_from_source_formulae: build_from_source_formulae + [formula.full_name],
          interactive:,
          keep_tmp:,
          debug_symbols:,
          force:,
          debug:,
          quiet:,
          verbose:,
        )
      rescue FormulaInstallationAlreadyAttemptedError
        # We already attempted to reinstall f as part of the dependency tree of
        # another formula. In that case, don't generate an error, just move on.
        nil
      rescue CannotInstallFormulaError, DownloadError => e
        ofail e
      rescue BuildError => e
        e.dump(verbose:)
        puts
        Homebrew.failed = true
      end
    end

    private_class_method def self.depends_on(one, two)
      if one.any_installed_keg
            &.runtime_dependencies
            &.any? { |dependency| dependency["full_name"] == two.full_name }
        1
      else
        one <=> two
      end
    end
  end
end
