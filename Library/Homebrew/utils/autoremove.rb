# typed: strict
# frozen_string_literal: true

module Utils
  # Helper function for finding autoremovable formulae.
  #
  # @private
  module Autoremove
    class << self
      sig { params(formulae: T::Array[Formula], casks: T::Array[Cask::Cask]).returns(T::Array[Formula]) }
      def removable_formulae(formulae, casks)
        unused_formulae = unused_formulae_with_no_formula_dependents(formulae)
        unused_formulae - formulae_with_cask_dependents(casks)
      end

      private

      sig { params(casks: T::Array[Cask::Cask]).returns(T::Array[Formula]) }
      def formulae_with_cask_dependents(casks)
        casks.flat_map { |cask| cask.depends_on[:formula] }.compact.flat_map do |name|
          f = begin
            Formulary.resolve(name)
          rescue FormulaUnavailableError
            nil
          end
          next [] unless f

          [f, *f.installed_runtime_formula_dependencies].compact
        end
      end

      sig { params(formulae: T::Array[Formula]).returns(T::Array[Formula]) }
      def bottled_formulae_with_no_formula_dependents(formulae)
        formulae_to_keep = T.let([], T::Array[Formula])
        formulae.each do |formula|
          keg = formula.any_installed_keg
          # Include current runtime dependencies to align with brew uninstall
          formulae_to_keep += formula.installed_runtime_formula_dependencies

          formulae_to_keep += formula.runtime_dependencies(read_from_tab: false,
                                                           undeclared:    false).filter_map do |dep|
            dep.to_formula
          rescue FormulaUnavailableError
            nil
          end

          tab = keg&.tab
          next unless tab
          next if tab.poured_from_bottle

          # Keep non-bottled formulae and their build dependencies
          formulae_to_keep << formula

          formulae_to_keep += formula.deps.select(&:build?).filter_map do |dep|
            dep.to_formula
          rescue FormulaUnavailableError
            nil
          end
        end
        names_to_keep = formulae_to_keep.to_set(&:name)
        formulae.reject { |f| names_to_keep.include?(f.name) }
      end

      # An array of {Formula} without {Formula} or {Cask}
      # dependents that weren't installed on request and without
      # build dependencies for {Formula} installed from source.
      # @private
      sig { params(formulae: T::Array[Formula]).returns(T::Array[Formula]) }
      def unused_formulae_with_no_formula_dependents(formulae)
        unused_formulae = bottled_formulae_with_no_formula_dependents(formulae).select do |f|
          tab = f.any_installed_keg&.tab
          next false unless tab

          tab.installed_on_request_present? ? tab.installed_on_request == false : false
        end

        unless unused_formulae.empty?
          unused_formulae += unused_formulae_with_no_formula_dependents(formulae - unused_formulae)
        end

        unused_formulae
      end
    end
  end
end
