# typed: strict
# frozen_string_literal: true

class Hash
  sig {
    type_parameters(:K2).params(
      other_hash: T::Hash[T.type_parameter(:K2), T.untyped],
      block:      T.nilable(T.proc.params(k: T.untyped, v1: T.untyped, v2: T.untyped).returns(T.untyped)),
    ).returns(T::Hash[T.any(Hash::K, T.type_parameter(:K2)), T.untyped])
  }
  def deep_merge(other_hash, &block); end

  sig {
    type_parameters(:K2).params(
      other_hash: T::Hash[T.type_parameter(:K2), T.untyped],
      block:      T.nilable(T.proc.params(k: T.untyped, v1: T.untyped, v2: T.untyped).returns(T.untyped)),
    ).returns(T::Hash[T.any(Hash::K, T.type_parameter(:K2)), T.untyped])
  }
  def deep_merge!(other_hash, &block); end
end
