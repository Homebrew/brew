# typed: strict

module OnSystem::MacOSAndLinux
  sig {
    type_parameters(:U)
      .params(block: T.proc.returns(T.type_parameter(:U)))
      .returns(T.nilable(T.type_parameter(:U)))
  }
  def on_macos(&block); end
end
