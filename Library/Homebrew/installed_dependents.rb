# typed: true
# frozen_string_literal: true

require "cask_dependent"

# Helper functions for installed dependents.
#
# @api private
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
  # parameter.
  #
  # For efficiency, we don't bother trying to get complete data.
  def find_some_installed_dependents(kegs, casks: [])
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
    dependents_to_check = (Formula.installed - keg_formulae) + (Cask::Caskroom.casks - casks)

    dependents_to_check.each do |dependent|
      required = case dependent
      when Formula
        dependent.missing_dependencies(hide: keg_names)
      when Cask::Cask
        # When checking for cask dependents, we don't care about missing or non-runtime dependencies
        CaskDependent.new(dependent).runtime_dependencies.map(&:to_formula)
      end

      required_kegs = required.map do |f|
        f_kegs = kegs_by_source[[f.name, f.tap]]
        next unless f_kegs

        f_kegs.max_by(&:version)
      end.compact

      next if required_kegs.empty?

      all_required_kegs += required_kegs
      all_dependents << dependent.to_s
    end

    return if all_required_kegs.empty?
    return if all_dependents.empty?

    [all_required_kegs.to_a, all_dependents.sort]
  end
end
