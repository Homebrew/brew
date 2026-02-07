# typed: strict

# This file contains temporary definitions for fixes that have
# been submitted upstream to https://github.com/sorbet/sorbet.

# https://github.com/sorbet/sorbet/pull/9864
class Integer
  sig {
    params(
      other: T.any(Integer, Float, Rational, BigDecimal),
    )
      .returns(Integer)
  }
  sig { params(other: T.anything).returns(T.nilable(Integer)) }
  def <=>(other); end
end
