# typed: strict

module OnSystem::MacOSOnly
  sig { params(arm: T.nilable(String), intel: T.nilable(String)).returns(T.nilable(String)) }
  def on_arch_conditional(arm: nil, intel: nil); end
end
