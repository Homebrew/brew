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
        unused_formulae - formulae_with_cask_dependents(casks)
      end

      private

      # An array of all installed {Formula} with {Cask} dependents.
      # @private
      sig { params(casks: T::Array[Cask::Cask]).returns(T::Array[Formula]) }
      def formulae_with_cask_dependents(casks)
        casks.flat_map { |cask| cask.depends_on[:formula] }
             .compact
             .map { |f| Formula[f] }
             .flat_map { |f| [f, *f.runtime_formula_dependencies].compact }
      end

      # An array of all installed {Formula} without runtime {Formula}
      # dependents for bottles and without build {Formula} dependents
      # for those built from source.
      # @private
      sig { params(formulae: T::Array[Formula]).returns(T::Array[Formula]) }
      def formulae_with_no_formula_dependents(formulae)
        dependents = T.let([], T::Array[Formula])
        formulae.each do |formula|
          dependents += formula.runtime_formula_dependencies

          # Ignore build dependencies when the formula is a bottle
          next if Tab.for_keg(formula.any_installed_keg).poured_from_bottle

          formula.deps.select(&:build?).each do |dep|
            dependents << dep.to_formula
          rescue FormulaUnavailableError
            # do nothing
          end
        end
        formulae - dependents
      end

      # Recursive function that returns an array of {Formula} without
      # {Formula} dependents that weren't installed on request.
      # @private
      sig { params(formulae: T::Array[Formula]).returns(T::Array[Formula]) }
      def unused_formulae_with_no_formula_dependents(formulae)
        unused_formulae = formulae_with_no_formula_dependents(formulae).reject do |f|
          Tab.for_keg(f.any_installed_keg).installed_on_request
        end

        unless unused_formulae.empty?
          unused_formulae += unused_formulae_with_no_formula_dependents(formulae - unused_formulae)
        end

        unused_formulae
      end
    end
  end
end
