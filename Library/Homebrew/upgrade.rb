# typed: strict
# frozen_string_literal: true

require "reinstall"
require "formula_installer"
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
        begin
          formulae_to_install = dependency_graph.tsort & formulae_to_install
        rescue TSort::Cyclic
          if Homebrew::EnvConfig.developer?
            raise CyclicDependencyError, dependency_graph.strongly_connected_components
          end
        end

        formulae_to_install.filter_map do |formula|
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
            fi.fetch_bottle_tab(quiet: !debug)

            all_runtime_deps_installed = fi.bottle_tab_runtime_dependencies.presence&.all? do |dependency, hash|
              minimum_version = if (version = hash["version"])
                Version.new(version)
              end
              Dependency.new(dependency).installed?(minimum_version:, minimum_revision: hash["revision"].to_i)
            end

            if !dry_run && dependents && all_runtime_deps_installed
              # Don't need to install this bottle if all of the runtime
              # dependencies have the same or newer version already installed.
              next
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
      end

      sig { params(formula_installers: T::Array[FormulaInstaller], dry_run: T::Boolean, verbose: T::Boolean).void }
      def upgrade_formulae(formula_installers, dry_run: false, verbose: false)
        valid_formula_installers = if dry_run
          formula_installers
        else
          Install.fetch_formulae(formula_installers)
        end

        valid_formula_installers.each do |fi|
          upgrade_formula(fi, dry_run:, verbose:)
          Cleanup.install_formula_clean!(fi.formula, dry_run:)
        end
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
               verbose: T::Boolean).void
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
                             verbose: false)
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

        upgradeable.reject! { |f| FormulaInstaller.installed.include?(f) }

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
          puts formulae_upgrades.join(", ")
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

      sig { params(formula_installer: FormulaInstaller, dry_run: T::Boolean, verbose: T::Boolean).void }
      def upgrade_formula(formula_installer, dry_run: false, verbose: false)
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

        Install.install_formula(formula_installer, upgrade: true)
      rescue BuildError => e
        e.dump(verbose:)
        puts
        Homebrew.failed = true
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

            LinkageChecker.new(keg, cache_db: db)
                          .broken_library_linkage?
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
