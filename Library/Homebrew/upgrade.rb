# typed: strict
# frozen_string_literal: true

require "reinstall"
require "formula_installer"
require "download_queue"
require "development_tools"
require "messages"
require "cleanup"
require "utils/topological_hash"
require "utils/output"

module Homebrew
  # Helper functions for upgrading formulae.
  module Upgrade
    extend Utils::Output::Mixin

    class Dependents < T::Struct
      const :upgradeable, T::Array[Formula]
      const :pinned, T::Array[Formula]
      const :skipped, T::Array[Formula]
    end

    class << self
      sig { params(upgrades: T::Array[String]).returns(T::Array[String]) }
      def format_upgrade_summary(upgrades)
        return upgrades if upgrades.size < 2

        name_width = upgrades.map { |upgrade| upgrade.split(" ", 2).fetch(0).length }.max
        name_width ||= 0
        old_version_width = upgrades.filter_map do |upgrade|
          versions = upgrade.split(" ", 2).fetch(1, "")
          next unless versions.include?(" -> ")

          versions.split(" -> ", 2).fetch(0).length
        end.max
        old_version_width ||= 0

        upgrades.map do |upgrade|
          parts = upgrade.split(" ", 2)
          name = parts.fetch(0)
          versions = parts.fetch(1, "")
          next name if versions.blank?

          if versions.include?(" -> ")
            version_parts = versions.split(" -> ", 2)
            old_version = version_parts.fetch(0)
            new_version = version_parts.fetch(1)
            "#{name.ljust(name_width)}  #{old_version.ljust(old_version_width)} -> #{new_version}"
          else
            "#{name.ljust(name_width)}  #{versions}"
          end
        end
      end

      sig {
        params(
          formulae_to_install: T::Array[Formula], flags: T::Array[String], dry_run: T::Boolean,
          force_bottle: T::Boolean, build_from_source_formulae: T::Array[String],
          dependents: T::Boolean, interactive: T::Boolean, keep_tmp: T::Boolean,
          debug_symbols: T::Boolean, force: T::Boolean, overwrite: T::Boolean,
          debug: T::Boolean, quiet: T::Boolean, verbose: T::Boolean
        ).returns(T::Array[FormulaInstaller])
      }
      def formula_installers(
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
        return [] if formulae_to_install.empty?

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
        sorted = dependency_graph.tsort_with_cycles do |cycles|
          raise CyclicDependencyError, cycles if Homebrew::EnvConfig.developer?

          odebug "Ignoring cyclic dependencies: #{cycles.map(&:to_sentence).join(", ")}"
        end
        formulae_to_install = sorted & formulae_to_install

        # We need to fetch the bottle tabs ahead of the `Install.fetch_formulae`
        # pipeline because we need to first filter out those formulae with all
        # runtime dependencies already satisfied (see below).
        download_queue = Homebrew::DownloadQueue.new
        begin
          installers = formulae_to_install.filter_map do |formula|
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
              fi.download_queue = download_queue
              fi.fetch_bottle_tab(quiet: !debug, enqueue: true)
              fi
            rescue CannotInstallFormulaError => e
              ofail e
              nil
            rescue UnsatisfiedRequirements, DownloadError => e
              ofail "#{formula}: #{e}"
              nil
            end
          end

          download_queue.fetch
        ensure
          download_queue.shutdown
        end

        installers.filter_map do |fi|
          fi.determine_bottle_tab_attributes

          if !dry_run && dependents
            all_runtime_deps_installed = fi.bottle_tab_runtime_dependencies.presence&.all? do |dependency, hash|
              minimum_version = if (version = hash["version"])
                Version.new(version)
              end
              Dependency.new(dependency).installed?(minimum_version:, minimum_revision: hash["revision"].to_i)
            end

            if all_runtime_deps_installed
              # Don't need to install this bottle if all of the runtime
              # dependencies have the same or newer version already installed.
              next
            end
          end

          if dry_run
            begin
              fi.check_install_sanity
            rescue CannotInstallFormulaError => e
              ofail e.message
              next
            end
          end

          fi
        end
      end

      sig {
        params(formula_installers: T::Array[FormulaInstaller], dry_run: T::Boolean, verbose: T::Boolean,
               fetch: T::Boolean, skip_formula_names: T::Array[String]).returns(T::Array[FormulaInstaller])
      }
      def upgrade_formulae(formula_installers, dry_run: false, verbose: false, fetch: true, skip_formula_names: [])
        valid_formula_installers = if dry_run || !fetch
          formula_installers
        else
          Install.fetch_formulae(formula_installers)
        end

        upgraded_formula_installers = valid_formula_installers.select do |fi|
          upgraded = upgrade_formula(fi, dry_run:, verbose:, skip_formula_names:)
          Cleanup.install_formula_clean!(fi.formula) if upgraded && !dry_run
          upgraded
        end
        return upgraded_formula_installers unless dry_run

        formulae_to_clean = Cleanup.install_cleanup_formulae(upgraded_formula_installers.map(&:formula))
        if formulae_to_clean.present? &&
           Cleanup.printed_dry_run_output?(Cleanup.dry_run_output(formulae: formulae_to_clean), ohai: true)
          Cleanup.puts_no_install_cleanup_disable_message_if_not_already!
        end
        upgraded_formula_installers
      end

      sig { params(formula: Formula).returns(T::Array[Keg]) }
      def outdated_kegs(formula)
        [formula, *formula.old_installed_formulae].map(&:linked_keg)
                                                  .select(&:directory?)
                                                  .map { |k| Keg.new(k.resolved_path) }
      end

      sig { params(formula: Formula, fi_options: Options).void }
      def print_upgrade_message(formula, fi_options)
        version_upgrade = if formula.optlinked?
          "#{Keg.new(formula.opt_prefix).version} -> #{formula.pkg_version}"
        else
          "-> #{formula.pkg_version}"
        end
        oh1 "Upgrading #{Formatter.identifier(formula.full_specified_name)}"
        puts "  #{version_upgrade} #{fi_options.to_a.join(" ")}"
      end

      sig {
        params(
          formulae: T::Array[Formula], flags: T::Array[String], dry_run: T::Boolean,
          ask: T::Boolean, installed_on_request: T::Boolean, force_bottle: T::Boolean,
          build_from_source_formulae: T::Array[String], interactive: T::Boolean,
          keep_tmp: T::Boolean, debug_symbols: T::Boolean, force: T::Boolean,
          debug: T::Boolean, quiet: T::Boolean, verbose: T::Boolean
        ).returns(Dependents)
      }
      def dependants(
        formulae,
        flags:,
        dry_run: false,
        ask: false,
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
        no_dependents = Dependents.new(upgradeable: [], pinned: [], skipped: [])
        if Homebrew::EnvConfig.no_installed_dependents_check?
          unless Homebrew::EnvConfig.no_env_hints?
            opoo <<~EOS
              `$HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK` is set: not checking for outdated
              dependents or dependents with broken linkage!
            EOS
          end
          return no_dependents
        end
        formulae_to_install = formulae.reject { |f| f.core_formula? && f.versioned_formula? }
        return no_dependents if formulae_to_install.empty?

        # TODO: this should be refactored to use FormulaInstaller new logic
        outdated = formulae_to_install.flat_map(&:runtime_installed_formula_dependents)
                                      .uniq
                                      .select(&:outdated?)

        # Ensure we never attempt a source build for outdated dependents of upgraded formulae.
        outdated, skipped = outdated.partition do |dependent|
          dependent.bottled? && dependent.deps.map(&:to_formula).all?(&:bottled?)
        end
        return no_dependents if outdated.blank?

        outdated -= formulae_to_install if dry_run
        upgradeable = outdated.reject(&:pinned?)
                              .sort { |a, b| depends_on(a, b) }
        pinned = outdated.select(&:pinned?)
                         .sort { |a, b| depends_on(a, b) }

        Dependents.new(upgradeable:, pinned:, skipped:)
      end

      sig {
        params(deps: Dependents, formulae: T::Array[Formula], flags: T::Array[String],
               dry_run: T::Boolean, installed_on_request: T::Boolean, force_bottle: T::Boolean,
               build_from_source_formulae: T::Array[String], interactive: T::Boolean, keep_tmp: T::Boolean,
               debug_symbols: T::Boolean, force: T::Boolean, debug: T::Boolean, quiet: T::Boolean,
               verbose: T::Boolean, skip_formula_names: T::Array[String]).void
      }
      def upgrade_dependents(deps, formulae,
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
                             verbose: false,
                             skip_formula_names: [])
        return if deps.blank?

        upgradeable = deps.upgradeable
        pinned      = deps.pinned
        skipped     = deps.skipped
        if pinned.present?
          plural = Utils.pluralize("dependent", pinned.count)
          opoo "Not upgrading #{pinned.count} pinned #{plural}:"
          puts(pinned.map do |f|
            "#{f.full_specified_name} #{f.pkg_version}"
          end.join(", "))
        end
        if skipped.present?
          opoo <<~EOS
            The following dependents of upgraded formulae are outdated but will not
            be upgraded because they are not bottled:
              #{skipped * "\n  "}
          EOS
        end

        upgradeable.reject! do |f|
          FormulaInstaller.installed.include?(f) || (dry_run && skip_formula_names.include?(f.full_name))
        end

        # Print the upgradable dependents.
        if upgradeable.present?
          installed_formulae = (dry_run ? formulae : FormulaInstaller.installed.to_a).dup
          formula_plural = Utils.pluralize("formula", installed_formulae.count)
          upgrade_verb = dry_run ? "Would upgrade" : "Upgrading"
          ohai "#{upgrade_verb} #{Utils.pluralize("dependent", upgradeable.count,
                                                  include_count: true)} of upgraded #{formula_plural}:"
          puts_no_installed_dependents_check_disable_message_if_not_already!
          formulae_upgrades = upgradeable.map do |f|
            name = f.full_specified_name
            if f.optlinked?
              "#{name} #{Keg.new(f.opt_prefix).version} -> #{f.pkg_version}"
            else
              "#{name} #{f.pkg_version}"
            end
          end
          puts format_upgrade_summary(formulae_upgrades).join("\n")
        end

        return if upgradeable.blank?

        unless dry_run
          dependent_installers = formula_installers(
            upgradeable,
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
          upgrade_formulae(dependent_installers, dry_run:, verbose:)
        end

        # Update non-core installed formulae for linkage checks after upgrading
        # Don't need to check core formulae because we do so at CI time.
        installed_non_core_formulae = FormulaInstaller.installed.to_a.reject(&:core_formula?)
        return if installed_non_core_formulae.blank?

        # Assess the dependents tree again now we've upgraded.
        unless dry_run
          oh1 "Checking for dependents of upgraded formulae..."
          puts_no_installed_dependents_check_disable_message_if_not_already!
        end

        broken_dependents = check_broken_dependents(installed_non_core_formulae)
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
          puts_no_installed_dependents_check_disable_message_if_not_already!
          puts reinstallable_broken_dependents.map(&:full_specified_name)
                                              .join(", ")
        end

        return if dry_run

        reinstall_contexts = reinstallable_broken_dependents.map do |formula|
          Reinstall.build_install_context(
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
        end

        valid_formula_installers = Install.fetch_formulae(reinstall_contexts.map(&:formula_installer))

        reinstall_contexts.each do |reinstall_context|
          next unless valid_formula_installers.include?(reinstall_context.formula_installer)

          Reinstall.reinstall_formula(reinstall_context)
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

      private

      sig {
        params(formula_installer: FormulaInstaller, dry_run: T::Boolean, verbose: T::Boolean,
               skip_formula_names: T::Array[String]).returns(T::Boolean)
      }
      def upgrade_formula(formula_installer, dry_run: false, verbose: false, skip_formula_names: [])
        formula = formula_installer.formula

        if dry_run
          Install.print_dry_run_dependencies(formula, formula_installer.compute_dependencies,
                                             skip_formula_names:) do |f|
            name = f.full_specified_name
            current_version = if f.optlinked?
              Keg.new(f.opt_prefix).version
            else
              f.installed_kegs.map(&:version).max
            end
            if current_version && current_version != f.pkg_version
              "#{name} #{current_version} -> #{f.pkg_version}"
            else
              "#{name} #{f.pkg_version}"
            end
          end
          return true
        end

        Install.install_formula(formula_installer, upgrade: true)
        true
      rescue BuildError => e
        e.dump(verbose:)
        puts
        Homebrew.failed = true
        false
      end

      sig { params(installed_formulae: T::Array[Formula]).returns(T::Array[Formula]) }
      def check_broken_dependents(installed_formulae)
        CacheStoreDatabase.use(:linkage) do |db|
          installed_formulae.flat_map(&:runtime_installed_formula_dependents)
                            .uniq
                            .select do |f|
            keg = f.any_installed_keg
            next unless keg
            next unless keg.directory?

            LinkageChecker.new(
              keg,
              cache_db: T.cast(db, CacheStoreDatabase[String, T::Hash[T.any(String, Symbol), T.anything]]),
            ).broken_library_linkage?
          end.compact
        end
      end

      sig { void }
      def puts_no_installed_dependents_check_disable_message_if_not_already!
        return if Homebrew::EnvConfig.no_env_hints?
        return if Homebrew::EnvConfig.no_installed_dependents_check?
        return if @puts_no_installed_dependents_check_disable_message_if_not_already

        puts "Disable this behaviour by setting `HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1`."
        puts "Hide these hints with `HOMEBREW_NO_ENV_HINTS=1` (see `man brew`)."
        @puts_no_installed_dependents_check_disable_message_if_not_already = T.let(true, T.nilable(T::Boolean))
      end

      sig {
        params(formula: Formula, flags: T::Array[String], force_bottle: T::Boolean,
               build_from_source_formulae: T::Array[String], interactive: T::Boolean,
               keep_tmp: T::Boolean, debug_symbols: T::Boolean, force: T::Boolean,
               overwrite: T::Boolean, debug: T::Boolean, quiet: T::Boolean, verbose: T::Boolean).returns(FormulaInstaller)
      }
      def create_formula_installer(
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
          installed_on_request = tab.installed_on_request == true
          build_bottle = tab.built_bottle?
        else
          link_keg = nil
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

      sig { params(one: Formula, two: Formula).returns(Integer) }
      def depends_on(one, two)
        if one.any_installed_keg
              &.runtime_dependencies
              &.any? { |dependency| dependency["full_name"] == two.full_name }
          1
        else
          T.must(one <=> two)
        end
      end
    end
  end
end
