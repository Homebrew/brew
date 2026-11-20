# typed: strict
# frozen_string_literal: true

class Symbol
  # @!visibility private
  sig { params(spec: Symbol).returns(Formula) }
  def f(spec = :stable)
    to_s.f(spec)
  end

  # @!visibility private
  sig { params(config: T.nilable(T::Hash[Symbol, T.untyped])).returns(Cask::Cask) }
  def c(config: nil)
    to_s.c(config:)
  end
end
