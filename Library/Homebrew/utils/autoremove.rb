# typed: strict
# frozen_string_literal: true

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

      private

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

          tab = f.any_installed_keg&.tab
          dep_names = if (tab_deps = T.cast(tab&.runtime_dependencies,
                                            T.nilable(T::Array[T::Hash[String, T.untyped]])))
            # Use tab data to avoid Formulary.resolve for each dependency.
            tab_deps.filter_map do |dep|
              full_name = dep["full_name"]
              next unless full_name

              Utils.name_from_full_name(full_name)
            end
          else
            # Fallback for pre-1.1.6 installations without tab runtime_dependencies.
            f.installed_runtime_formula_dependencies.map(&:name)
          end
          [base, *dep_names]
        end
        names.to_set
      end

      # An array of all installed bottled {Formula} without runtime {Formula}
      # dependents for bottles and without build {Formula} dependents
      # for those built from source.
      # @private
      sig { params(formulae: T::Array[Formula]).returns(T::Array[Formula]) }
      def bottled_formulae_with_no_formula_dependents(formulae)
        names_to_keep = T.let(Set.new, T::Set[String])
        formulae.each do |formula|
          tab = formula.any_installed_keg&.tab
          if (tab_deps = T.cast(tab&.runtime_dependencies, T.nilable(T::Array[T::Hash[String, T.untyped]])))
            # Use tab data to avoid Formulary.resolve for each dependency.
            tab_deps.each do |dep|
              full_name = dep["full_name"]
              next unless full_name

              names_to_keep.add(Utils.name_from_full_name(full_name))
            end
          else
            # Fallback for pre-1.1.6 installations without tab runtime_dependencies.
            formula.installed_runtime_formula_dependencies.each { |f| names_to_keep.add(f.name) }
          end

          if tab
            # Ignore build dependencies when the formula is a bottle
            next if tab.poured_from_bottle

            # Keep the formula if it was built from source
            names_to_keep.add(formula.name)
          end

          formula.deps.select(&:build?).each do |dep|
            names_to_keep.add(dep.to_formula.name)
          rescue FormulaUnavailableError
            # do nothing
          end
        end
        formulae.reject { |f| names_to_keep.intersect?(f.possible_names) }
      end

      # Recursive function that returns an array of {Formula} without
      # {Formula} dependents that weren't installed on request.
      # @private
      sig { params(formulae: T::Array[Formula]).returns(T::Array[Formula]) }
      def unused_formulae_with_no_formula_dependents(formulae)
        unused_formulae = bottled_formulae_with_no_formula_dependents(formulae).select do |f|
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
