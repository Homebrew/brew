# typed: strict

module SharedEnvExtension
  # Overload to allow `PATH` values.
  sig {
    type_parameters(:U).params(
      key:   String,
      value: T.all(T.type_parameter(:U), T.nilable(T.any(String, PATH))),
    ).returns(T.type_parameter(:U))
  }
  def []=(key, value); end
end
