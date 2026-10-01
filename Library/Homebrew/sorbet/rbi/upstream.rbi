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

# https://github.com/sorbet/sorbet/pull/10666
class JSON::Coder
  sig {
    params(
      options:   T.nilable(T::Hash[Symbol, T.anything]),
      kwoptions: T.anything,
      as_json:   T.nilable(T.proc.params(object: T.anything).returns(T.anything)),
    )
      .void
  }
  def initialize(options = nil, **kwoptions, &as_json); end

  sig { params(object: T.anything).returns(String) }
  sig {
    type_parameters(:IO)
      .params(
        object: T.anything,
        io:     T.type_parameter(:IO),
      )
      .returns(T.type_parameter(:IO))
  }
  def dump(object, io = nil); end
end
