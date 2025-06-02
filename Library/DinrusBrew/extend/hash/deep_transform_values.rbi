# typed: strict

class Hash
  sig {
    type_parameters(:out).params(
      block: T.proc.params(o: Hash::V).returns(T.type_parameter(:out)),
    ).returns(T::Hash[Hash::K, T.type_parameter(:out)])
  }
  def deep_transform_values(&block); end

  sig {
    type_parameters(:out).params(
      block: T.proc.params(o: Hash::V).returns(T.type_parameter(:out)),
    ).returns(T::Hash[Hash::K, T.type_parameter(:out)])
  }
  def deep_transform_values!(&block); end
end
