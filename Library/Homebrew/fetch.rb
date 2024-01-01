# typed: strict
# frozen_string_literal: true

module Homebrew
  # @api private
  module Fetch
    sig {
      params(
        formula:                    Formula,
        force_bottle:               T::Boolean,
        bottle_tag:                 T.nilable(Symbol),
        build_from_source_formulae: T::Array[String],
        os:                         T.nilable(Symbol),
        arch:                       T.nilable(Symbol),
      ).returns(T::Boolean)
    }
    def fetch_bottle?(formula, force_bottle:, bottle_tag:, build_from_source_formulae:, os:, arch:)
      bottle = formula.bottle

      return true if force_bottle && bottle.present?
      if os.present?
        return true
      elsif ENV["HOMEBREW_TEST_GENERIC_OS"].present?
        # `:generic` bottles don't exist, and `--os` flag is not specified.
        return false
      end
      return true if arch.present?
      return true if bottle_tag.present? && formula.bottled?(bottle_tag)

      bottle.present? &&
        formula.pour_bottle? &&
        build_from_source_formulae.exclude?(formula.full_name) &&
        bottle.compatible_locations?
    end
  end
end
