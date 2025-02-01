# typed: strict

module OnSystem::MacOSOnly
  sig { params(arm: T.nilable(String), intel: T.nilable(String)).returns(T.nilable(String)) }
  def on_arch_conditional(arm: nil, intel: nil); end
end

module OnSystem::MacOSAndLinux
  sig { params(macos: T.nilable(String), linux: T.nilable(String)).returns(T.nilable(String)) }
  def on_system_conditional(macos: nil, linux: nil); end

  sig { params(arm: T.nilable(String), intel: T.nilable(String)).returns(T.nilable(String)) }
  def on_arch_conditional(arm: nil, intel: nil); end
end
