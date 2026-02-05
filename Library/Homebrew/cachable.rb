# typed: strict
# frozen_string_literal: true

module Cachable
  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def cache
    @cache ||= T.let({}, T.nilable(T::Hash[T.untyped, T.untyped]))
  end

  sig { void }
  def clear_cache
    cache.clear
  end
end
