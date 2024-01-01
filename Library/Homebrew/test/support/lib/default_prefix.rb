# typed: strict
# frozen_string_literal: true

module Homebrew
  # For testing's sake always assume the default prefix
  DEFAULT_PREFIX = T.let(HOMEBREW_PREFIX.to_s.freeze, String)
  DEFAULT_REPOSITORY = T.let(HOMEBREW_REPOSITORY.to_s.freeze, String)
end
