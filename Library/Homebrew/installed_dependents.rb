# typed: strict
# frozen_string_literal: true

require "cask_dependent"

# Helper functions for installed dependents.
module InstalledDependents
  module_function

  # Given an array of kegs, this method will try to find some other kegs
  # or casks that depend on them. If it does, it returns:
  #
  # - some kegs in the passed array that have installed dependents
  # - some installed dependents of those kegs.
  #
  # If it doesn't, it returns nil.
  #
  # Note that nil will be returned if the only installed dependents of the
  # passed kegs are other kegs in the array or casks present in the casks
  # parameter, or formulae excluded from the formulae parameter.
  #
  # For efficiency, we don't bother trying to get complete data.
  sig {
    params(
      kegs:     T::Array[Keg],
      casks:    T::Array[Cask::Cask],
      formulae: T::Array[Formula],
    ).returns(T.nilable([T::Array[Keg], T::Array[String]]))
  }
  def find_some_installed_dependents(kegs, casks: [], formulae: Formula.installed)
    keg_names = kegs.select(&:optlinked?).map(&:name)
    keg_formulae = []
    kegs_by_source = kegs.group_by do |keg|
      # First, attempt to resolve the keg to a formula
      # to get up-to-date name and tap information.
      f = keg.to_formula
      keg_formulae << f
      [f.name, f.tap]
    rescue
      # If the formula for the keg can't be found,
      # fall back to the information in the tab.
      [keg.name, keg.tab.tap]
    end

    all_required_kegs = Set.new
    all_dependents = []

    # Don't include dependencies of kegs that were in the given array.
    dependents_to_check = (formulae - keg_formulae) + (Cask::Caskroom.casks - casks)

    dependents_to_check.each do |dependent|
      required_kegs = case dependent
      when Formula
        dependent.missing_dependencies(hide: keg_names).flat_map do |d|
          formula = begin
            d.to_installed_formula
          rescue FormulaUnavailableError, Homebrew::UntrustedTapError, TapFormulaAmbiguityError => e
            next [] unless d.formula_name?

            loaders = e.is_a?(TapFormulaAmbiguityError) ? e.loaders : d.formula_loaders
            matching_kegs = loaders.filter_map do |loader|
              kegs_by_source[[loader.name, loader.tap]]&.max_by(&:scheme_and_version)
            end
            if matching_kegs.empty?
              fallback_names = [Utils.name_from_full_name(d.name)]
              fallback_names.concat(loaders.map { |loader| Utils.name_from_full_name(loader.name) })
              known_taps = loaders.filter_map(&:tap)
              dependency_tap = d.tap
              known_taps << dependency_tap if dependency_tap
              matching_kegs = kegs_by_source.filter_map do |(name, tap), source_kegs|
                next unless fallback_names.include?(name)
                next if tap && known_taps.any? && known_taps.exclude?(tap)

                source_kegs.max_by(&:scheme_and_version)
              end
            end
            next matching_kegs
          end
          f_kegs = kegs_by_source[[formula.name, formula.tap]]
          [f_kegs&.max_by(&:scheme_and_version)].compact
        end
      when Cask::Cask
        # When checking for cask dependents, we don't care about missing or non-runtime dependencies
        CaskDependent.new(dependent).runtime_dependencies.filter_map do |d|
          source = begin
            f = d.to_installed_formula
            [f.name, f.tap]
          rescue FormulaUnavailableError, Homebrew::UntrustedTapError
            [Utils.name_from_full_name(d.name), d.tap]
          end
          kegs_by_source[source]&.max_by(&:scheme_and_version)
        end
      end

      next if required_kegs.empty?

      all_required_kegs += required_kegs
      all_dependents << dependent.to_s
    end

    return if all_required_kegs.empty?
    return if all_dependents.empty?

    [all_required_kegs.to_a, all_dependents.sort]
  end

  # Given an array of kegs, this method finds the installed formulae that
  # `brew autoremove` keeps them for as build dependencies. If there are any,
  # it returns:
  #
  # - the kegs in the passed array that are kept for them
  # - the names of those formulae.
  #
  # If there are none, it returns nil.
  sig { params(kegs: T::Array[Keg]).returns(T.nilable([T::Array[Keg], T::Array[String]])) }
  def find_installed_build_dependents(kegs)
    # An older keg can go while another one stays, unless `opt` points to it.
    last_or_linked_kegs = kegs.select do |keg|
      keg.optlinked? || keg.rack.subdirs.all? { |dir| kegs.include?(Keg.new(dir)) }
    end
    names_by_keg = last_or_linked_kegs.to_h do |keg|
      [keg, keg.to_formula.possible_names]
    rescue FormulaUnavailableError, TapFormulaAmbiguityError, Homebrew::UntrustedTapError, FormulaSpecificationError
      [keg, [keg.name]]
    end
    keg_names = kegs.map(&:name)
    # Don't include build dependencies of formulae that keep none of their kegs.
    remaining_formulae = Formula.installed.reject do |f|
      keg_names.intersect?(f.possible_names) && (f.installed_kegs - kegs).empty?
    end
    build_dependents = build_dependents_by_name(remaining_formulae, Formula.installed, removed_kegs: kegs)
    dependents_by_keg = names_by_keg.transform_values { |names| build_dependents.values_at(*names).flatten.compact }
                                    .reject { |_, dependents| dependents.empty? }
    return if dependents_by_keg.empty?

    [dependents_by_keg.keys, dependents_by_keg.values.flatten.uniq.sort]
  end

  # The names of the runtime dependencies of `formulae` and of the build
  # dependencies in {build_dependents_by_name}.
  sig { params(formulae: T::Array[Formula], installed: T::Array[Formula]).returns(T::Set[String]) }
  def names_of_dependencies_to_keep(formulae, installed)
    build_dependents_by_name(formulae, installed).keys
                                                 .to_set
                                                 .merge(formulae.flat_map(&:installed_runtime_dependency_names))
  end

  # The names of the build dependencies to keep, each with the names of the
  # `formulae` that need it. Build dependencies are kept for {Formula} built
  # from source or without a usable bottle. Those built from source are
  # always kept, as a bottle may not be usable by the next upgrade and they
  # take a while to install again.
  sig {
    params(formulae: T::Array[Formula], installed: T::Array[Formula], removed_kegs: T::Array[Keg])
      .returns(T::Hash[String, T::Array[String]])
  }
  def build_dependents_by_name(formulae, installed, removed_kegs: [])
    dependents = T.let({}, T::Hash[String, T::Array[String]])
    names_by_dependency = T.let({}, T::Hash[String, T::Array[String]])
    built_from_source_names = installed.reject { |f| f.any_installed_keg&.tab&.poured_from_bottle }
                                       .flat_map(&:possible_names)
                                       .to_set
    formulae.each do |formula|
      keg = formula.any_installed_keg
      # Read the install receipt that is left once `removed_kegs` are gone.
      keg = (formula.installed_kegs - removed_kegs).last if keg && removed_kegs.include?(keg)
      tab = keg&.tab
      # Pouring a bottle doesn't use build dependencies
      pours_bottle = tab&.poured_from_bottle && formula.bottled? && formula.pour_bottle?

      formula.deps.select(&:build?).each do |dep|
        next if pours_bottle && built_from_source_names.exclude?(Utils.name_from_full_name(dep.name))

        # Many formulae share a build dependency, so look each one up once.
        dependency_names = names_by_dependency[dep.name] ||= begin
          [dep.to_formula.name]
        rescue TapFormulaAmbiguityError => e
          e.loaders.map(&:name)
        rescue Homebrew::UntrustedTapError, FormulaSpecificationError, FormulaUnavailableError
          dep.formula_name? ? dep.formula_loaders.map(&:name) : []
        end
        dependency_names.each do |dependency_name|
          dependents[dependency_name] = dependents.fetch(dependency_name, []) + [formula.name]
        end
      end
    end
    dependents
  end

  # Filters out the dependencies of everything that stays installed, including
  # earlier removal candidates.
  sig { params(removable: T::Array[Formula], installed: T::Array[Formula]).returns(T::Array[Formula]) }
  def formulae_safe_to_remove(removable, installed)
    # Each pass keeps at least one more formula or is the last one.
    removable.length.times do
      names_to_keep = names_of_dependencies_to_keep(installed - removable, installed)
      still_removable = removable.reject { |f| names_to_keep.intersect?(f.possible_names) }
      break if still_removable.length == removable.length

      removable = still_removable
    end
    removable
  end

  # The commands that stop `formulae` from requiring the formulae in
  # `dependency_names`, which maps their possible names to their full names.
  # An outdated dependent is upgraded when its latest version no longer needs
  # them.
  # With `all_dependents`, every one of `formulae` is known to require one of
  # them, whatever name it lists it under.
  sig {
    params(dependency_names: T::Hash[String, String], formulae: T::Array[Formula], all_dependents: T::Boolean)
      .returns(T::Array[String])
  }
  def commands_to_drop_dependencies(dependency_names, formulae, all_dependents: false)
    kept_dependencies = T.let([], T::Array[String])
    droppers = T.let([], T::Array[[Formula, T::Array[String]]])
    full_names = ->(deps) { deps.filter_map { |dep| dependency_names[Utils.name_from_full_name(dep.name)] } }

    formulae.each do |dependent|
      installed_dependency_names = full_names.call(dependent.runtime_dependencies(stop_at_untrusted: true))
      # A dependent that lists a dependency under another name, such as an alias, keeps requiring it.
      return [] if all_dependents && installed_dependency_names.empty?
      next if installed_dependency_names.empty?

      # Unlike `runtime_dependencies`, this raises when a dependency cannot be loaded.
      declared_dependencies = dependent.recursive_dependencies do |formula, dep|
        next Dependable::PRUNE if dep.build? || dep.test?
        next if dep.required? || !formula.is_a?(Formula)

        # An upgrade keeps the options that each formula was installed with, so a recommended dependency
        # stays unless it was opted out of and an optional one only when it was selected. An older install
        # receipt does not list the options that its formula has gained since.
        used_options = Tab.for_formula(formula).used_options
        selected = if dep.recommended?
          dep.option_names.none? { |name| used_options.include?("without-#{name}") }
        else
          dep.option_names.any? { |name| used_options.include?("with-#{name}") }
        end
        Dependable::PRUNE unless selected
      end
      declared_dependency_names = full_names.call(declared_dependencies)
      dropped = installed_dependency_names - declared_dependency_names
      # Only an upgrade changes what a dependent requires, and a disabled formula cannot be upgraded.
      dropped = [] if dropped.any? && (!dependent.outdated? || dependent.disabled?)
      # An upgrade can also make a dependent require a dependency that its receipt does not list.
      kept_dependencies.concat(installed_dependency_names - dropped, declared_dependency_names)
      droppers << [dependent, dropped]
    rescue FormulaUnavailableError, TapFormulaAmbiguityError, FormulaSpecificationError, Homebrew::UntrustedTapError
      # Its latest dependencies cannot be read, so this dependent keeps what its receipt lists.
      kept_dependencies.concat(installed_dependency_names.to_a)
    end

    # An uninstall stays refused while any of the dependencies is still required.
    return [] if all_dependents && kept_dependencies.any?

    # A command only helps when no other dependent keeps requiring what it drops.
    outdated = droppers.filter_map { |dependent, dropped| dependent if (dropped - kept_dependencies).any? }
    {
      "unpin"   => outdated.select(&:pinned?),
      "upgrade" => outdated,
    }.filter_map do |command, dependents|
      ["brew", command, *dependents.map(&:full_name).uniq.sort].join(" ") if dependents.any?
    end
  end

  # Removes the dependencies from the install receipts of `formulae` that
  # installing them again would no longer list. A receipt lists all runtime
  # dependencies from install time, so it goes stale when a dependency drops
  # one of its own and the dependent is not rebuilt. An installed dependency
  # goes when none of `formulae` that list it still declares it, the
  # dependent's dependency tree no longer has it and its keg does not link to it.
  sig { params(formulae: T::Array[Formula], dry_run: T::Boolean).void }
  def prune_stale_dependencies(formulae, dry_run: false)
    declared_names = formulae.to_h { |f| [f.name, f.deps.map { |dep| Utils.name_from_full_name(dep.name) }] }
    receipt_name = ->(dep) { Utils.name_from_full_name(dep["full_name"]) if dep.is_a?(Hash) && dep["full_name"] }
    receipts = formulae.filter_map do |dependent|
      keg = dependent.any_installed_keg
      tab_dependencies = keg&.runtime_dependencies
      next if keg.nil? || tab_dependencies.nil?

      tab_names = tab_dependencies.filter_map(&receipt_name)
      # The dependent or one of its dependencies declares nearly every dependency.
      undeclared_names = tab_names - declared_names.values_at(dependent.name, *tab_names).flatten
      [dependent, keg, tab_dependencies, tab_names - undeclared_names, undeclared_names]
    end
    # A dependency that a formula still declares stays installed, whatever the other receipts list.
    declared_somewhere = receipts.flat_map { |_, _, _, names, _| names }.to_set
    # A receipt can list a formula under the name it had before it was renamed.
    possible_names = T.let({}, T::Hash[String, T::Array[String]])
    current_names = ->(deps) { deps.flat_map { |dep| possible_names[dep.name] ||= dep.to_formula.possible_names } }
    pruned = T.let(false, T::Boolean)

    # Every keg's linkage comes from the same cache, which is only read when a receipt gets this far.
    CacheStoreDatabase.use(:linkage) do
      receipts.each do |dependent, keg, tab_dependencies, _, undeclared_names|
        stale_names = undeclared_names.reject { |name| declared_somewhere.include?(name) }
                                      .select { |name| (HOMEBREW_PREFIX/"opt"/name).directory? }
        next if stale_names.empty?
        # An upgrade writes a new receipt.
        next if keg.version != dependent.pkg_version
        # An alias may have moved on to another formula while the keg still uses the one in the receipt.
        next if dependent.deps.any? { |dep| dep.to_formula.name != Utils.name_from_full_name(dep.name) }

        stale_names -= current_names.call(dependent.recursive_dependencies)
        next if stale_names.empty?

        # Installing again keeps the keg, so the receipt would still list what the keg links to.
        stale_names -= current_names.call(dependent.runtime_dependencies(read_from_tab: false))
        next if stale_names.empty?

        tab_dependencies.delete_if { |dep| stale_names.include?(receipt_name.call(dep)) }
        tab = keg.tab
        tab.runtime_dependencies = tab_dependencies
        tab.write unless dry_run
        pruned = true
      rescue FormulaUnavailableError, TapFormulaAmbiguityError, FormulaSpecificationError, Homebrew::UntrustedTapError
        # The dependency tree cannot be read, so the receipt stays as it is.
        next
      end
    end
    return unless pruned

    # What was read from the receipts before now is cached.
    [:runtime_dependencies, :runtime_formula_dependencies, :installed_runtime_formula_dependencies,
     :runtime_installed_formula_dependents].each { |key| Formula.cache.delete(key) }
  end
end
