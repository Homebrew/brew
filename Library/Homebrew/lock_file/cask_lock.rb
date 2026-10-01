# typed: strict
# frozen_string_literal: true

# A lock file for a cask.
class CaskLock < LockFile
  sig { params(cask_token: String).void }
  def initialize(cask_token)
    super(:cask, HOMEBREW_PREFIX/"Caskroom/#{cask_token}")
  end
end
