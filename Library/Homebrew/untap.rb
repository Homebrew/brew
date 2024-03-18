# typed: true
# frozen_string_literal: true

require "extend/cachable"

module Homebrew
  # Helpers for the `brew untap` command.
  # @api private
  module Untap
    extend Cachable

    # All installed formulae currently available in a tap by formula full name.
    sig { params(tap: Tap).returns(T::Array[Formula]) }
    def self.installed_formulae_for(tap:)
      tap.formula_names.filter_map do |formula_name|
        next unless installed_formulae_names.include?(T.must(formula_name.split("/").last))

        formula = begin
          Formulary.factory(formula_name)
        rescue FormulaUnavailableError
          # Don't blow up because of a single unavailable formula.
          next
        end

        # Can't use Formula#any_version_installed? because it doesn't consider
        # taps correctly.
        formula if formula.installed_kegs.any? { |keg| keg.tab.tap == tap }
      end
    end

    sig { returns(T::Set[String]) }
    def self.installed_formulae_names
      cache[:installed_formulae_names] ||= Formula.installed_formula_names.to_set.freeze
    end
    private_class_method :installed_formulae_names

    # All installed casks currently available in a tap by cask full name.
    sig { params(tap: Tap).returns(T::Array[Cask::Cask]) }
    def self.installed_casks_for(tap:)
      tap.cask_tokens.filter_map do |cask_token|
        next unless installed_cask_tokens.include?(T.must(cask_token.split("/").last))

        cask = begin
          Cask::CaskLoader.load(cask_token)
        rescue Cask::CaskUnavailableError
          # Don't blow up because of a single unavailable cask.
          next
        end

        cask if cask.installed?
      end
    end

    sig { returns(T::Set[String]) }
    def self.installed_cask_tokens
      cache[:installed_cask_tokens] ||= Cask::Caskroom.tokens.to_set.freeze
    end
    private_class_method :installed_cask_tokens
  end
end
