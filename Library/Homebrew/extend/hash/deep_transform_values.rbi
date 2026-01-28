# typed: strict

class Hash
  sig {
    type_parameters(:Out).params(
      block: T.proc.params(o: Hash::V).returns(T.type_parameter(:Out)),
    ).returns(T::Hash[Hash::K, T.type_parameter(:Out)])
  }
  def deep_transform_values(&block); end

  sig {
    type_parameters(:Out).params(
      block: T.proc.params(o: Hash::V).returns(T.type_parameter(:Out)),
    ).returns(T::Hash[Hash::K, T.type_parameter(:Out)])
  }
  def deep_transform_values!(&block); end
end
