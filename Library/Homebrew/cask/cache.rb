# typed: strict
# frozen_string_literal: true

module Cask
  # Helper functions for the cask cache.
  module Cache
    sig { returns(Pathname) }
    def self.path
      @path ||= T.let(HOMEBREW_CACHE/"Cask", T.nilable(Pathname))
    end
  end
end
