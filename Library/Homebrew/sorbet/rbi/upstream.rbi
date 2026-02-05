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
  sig { params(other: T.anything).returns(NilClass) }
  def <=>(other); end
end

# https://github.com/sorbet/sorbet/pull/9847
class IO
  # Waits until IO is readable and returns a truthy value, or a falsy value when
  # times out. Returns a truthy value immediately when buffered data is available.
  #
  # You must require 'io/wait' to use this method.
  sig { params(timeout: T.nilable(T.any(Float, Integer, Rational))).returns(T.nilable(T.any(IO, T::Boolean))) }
  def wait_readable(timeout = nil); end
end
