# typed: strict
# frozen_string_literal: true

module Service
  module Formulae
    # All available services, with optional filters applied
    # @private
    sig { params(loaded: T.nilable(T::Boolean), skip_root: T::Boolean).returns(T::Array[Service::FormulaWrapper]) }
    def self.available_services(loaded: nil, skip_root: false)
      require "formula"

      formulae = Formula.installed
                        .map { |formula| FormulaWrapper.new(formula) }
                        .select(&:service?)
                        .sort_by(&:name)

      formulae = formulae.select { |formula| formula.loaded? == loaded } unless loaded.nil?
      formulae = formulae.reject { |formula| formula.owner == "root" } if skip_root

      formulae
    end

    # List all available services with status, user, and path to the file.
    sig { returns(T::Array[T::Hash[T.untyped, T.untyped]]) }
    def self.services_list
      available_services.map(&:to_hash)
    end
  end
end
