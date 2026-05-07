# typed: strict

# Not a real formula, just a Sorbet shim for external taps.
# rubocop:disable FormulaAudit/Desc,FormulaAudit/Homepage
class PortableFormula < Formula
  extend T::Generic

  # This is required for type checking on official taps to initially succeed
  # This could also be added to homebrew-core/Abstract/portable-formula.rb and subsequently removed here
  # rubocop:disable Style/MutableConstant
  Cache = type_template { { fixed: T::Hash[Symbol, T.untyped] } }
  # rubocop:enable Style/MutableConstant
end
# rubocop:enable FormulaAudit/Desc,FormulaAudit/Homepage
