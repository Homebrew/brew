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
          rescue FormulaUnavailableError
            next []
          rescue Homebrew::UntrustedTapError, TapFormulaAmbiguityError => e
            loaders = begin
              if e.is_a?(TapFormulaAmbiguityError)
                e.loaders
              else
                [Formulary.loader_for(d.name, warn: false)]
              end
            rescue TapFormulaAmbiguityError => ambiguity
              ambiguity.loaders
            end
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
        CaskDependent.new(dependent).runtime_dependencies.map(&:to_installed_formula).filter_map do |f|
          kegs_by_source[[f.name, f.tap]]&.max_by(&:scheme_and_version)
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
end
