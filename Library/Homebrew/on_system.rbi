# typed: strict

module OnSystem::MacOSOnly
  sig { params(arm: T.nilable(String), intel: T.nilable(String)).returns(T.nilable(String)) }
  def on_arch_conditional(arm: nil, intel: nil); end
end

module OnSystem::MacOSAndLinux
  sig {
    params(
      macos: T.nilable(T.any(T::Array[T.any(String, Pathname)], String, Pathname)),
      linux: T.nilable(T.any(T::Array[T.any(String, Pathname)], String, Pathname)),
    ).returns(T.nilable(T.any(T::Array[T.any(String, Pathname)], String, Pathname)))
  }
  def on_system_conditional(macos: nil, linux: nil); end

  sig {
    type_parameters(:U)
      .params(block: T.proc.returns(T.type_parameter(:U)))
      .returns(T.type_parameter(:U))
  }
  def on_macos(&block); end

  sig { params(arm: T.nilable(String), intel: T.nilable(String)).returns(T.nilable(String)) }
  def on_arch_conditional(arm: nil, intel: nil); end
end
