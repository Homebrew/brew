# typed: strict
# frozen_string_literal: true

class Symbol
  # @!visibility private
  sig { params(args: Integer).returns(Formula) }
  def f(*args)
    to_s.f(*args)
  end

  # @!visibility private
  sig { params(config: T.nilable(T::Hash[Symbol, T.untyped])).returns(Cask::Cask) }
  def c(config: nil)
    to_s.c(config:)
  end
end
