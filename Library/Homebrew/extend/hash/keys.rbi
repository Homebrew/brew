# typed: strict
# frozen_string_literal: true

class Hash
  sig {
    type_parameters(:out).params(
      block: T.proc.params(o: K).returns(T.type_parameter(:out)),
    ).returns(T::Hash[T.type_parameter(:out), V])
  }
  def deep_transform_keys(&block); end

  sig {
    type_parameters(:out).params(
      block: T.proc.params(o: K).returns(T.type_parameter(:out)),
    ).returns(T::Hash[T.type_parameter(:out), V])
  }
  def deep_transform_keys!(&block); end

  sig { returns(T::Hash[String, V]) }
  def deep_stringify_keys; end

  sig { returns(T::Hash[String, V]) }
  def deep_stringify_keys!; end

  sig { returns(T::Hash[Symbol, V]) }
  def deep_symbolize_keys; end

  sig { returns(T::Hash[Symbol, V]) }
  def deep_symbolize_keys!; end
end
