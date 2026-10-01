# typed: strict
# frozen_string_literal: true

module Cacheable
  extend T::Generic

  # Sorbet type members are mutable by design and cannot be frozen.
  Cache = type_member { { upper: T::Hash[T.anything, T.anything] } }
  sig { returns(Cache) }
  def cache
    @cache ||= T.let(T.cast({}, Cache), T.nilable(Cache))
  end

  sig { void }
  def clear_cache
    cache.clear
  end
end
