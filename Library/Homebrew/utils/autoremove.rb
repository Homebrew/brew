# typed: strict
# frozen_string_literal: true

require "installed_dependents"

module Utils
  # Helper function for finding autoremovable formulae.
  #
  # @private
  module Autoremove
    class << self
      # An array of {Formula} without {Formula} or {Cask}
      # dependents that weren't installed on request and without
      # build dependencies for {Formula} installed from source.
      # @private
      sig { params(formulae: T::Array[Formula], casks: T::Array[Cask::Cask]).returns(T::Array[Formula]) }
      def removable_formulae(formulae, casks)
        unused_formulae = unused_formulae_with_no_formula_dependents(formulae)
        cask_dep_names = cask_dependent_formula_names(casks, formulae)
        unused_formulae.reject { |f| cask_dep_names.intersect?(f.possible_names) }
      end

      # A set of names for all installed {Formula} objects that are {Cask} formula
      # dependencies (direct or transitive).
      # @private
      sig { params(casks: T::Array[Cask::Cask], formulae: T::Array[Formula]).returns(T::Set[String]) }
      def cask_dependent_formula_names(casks, formulae)
        formulae_by_name = formulae.to_h { |f| [f.name, f] }
        names = casks.flat_map { |cask| cask.depends_on.formula }.flat_map do |name|
          base = Utils.name_from_full_name(name)
          f = formulae_by_name[base]
          next [] unless f

          [base, *f.installed_runtime_dependency_names]
        end
        names.to_set
      end

      # An array of all installed {Formula} that aren't dependencies to keep.
      # @private
      sig { params(formulae: T::Array[Formula]).returns(T::Array[Formula]) }
      def formulae_with_no_formula_dependents(formulae)
        names_to_keep = InstalledDependents.names_of_dependencies_to_keep(formulae, formulae)
        formulae.reject { |f| names_to_keep.intersect?(f.possible_names) }
      end

      # Recursive function that returns an array of {Formula} without
      # {Formula} dependents that weren't installed on request.
      # @private
      sig { params(formulae: T::Array[Formula]).returns(T::Array[Formula]) }
      def unused_formulae_with_no_formula_dependents(formulae)
        unused_formulae = formulae_with_no_formula_dependents(formulae).select do |f|
          tab = f.any_installed_keg&.tab
          next unless tab
          next unless tab.installed_on_request_present?

          tab.installed_on_request == false
        end

        unless unused_formulae.empty?
          unused_formulae += unused_formulae_with_no_formula_dependents(formulae - unused_formulae)
        end

        unused_formulae
      end
    end
  end
end
