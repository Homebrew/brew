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
end
