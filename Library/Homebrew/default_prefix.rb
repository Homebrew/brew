# typed: strict
# frozen_string_literal: true

module Homebrew
  DEFAULT_PREFIX = T.let(ENV.fetch("HOMEBREW_DEFAULT_PREFIX").freeze, String)
  DEFAULT_REPOSITORY = T.let(ENV.fetch("HOMEBREW_DEFAULT_REPOSITORY").freeze, String)
end
