# typed: strict
# frozen_string_literal: true

module Cask
  # Helper functions for the cask cache.
  #
  # @api private
  module Cache
    sig { returns(Pathname) }
    def self.path
      @path ||= T.let(HOMEBREW_CACHE/"Cask", T.nilable(Pathname))
    end
  end
end
