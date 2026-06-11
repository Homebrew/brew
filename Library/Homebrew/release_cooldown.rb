# typed: strict
# frozen_string_literal: true

module Homebrew
  # The number of days a new upstream release must have been published before
  # Homebrew tooling will use it, configurable with
  # `$HOMEBREW_RELEASE_COOLDOWN_DAYS`. A value of `0` disables the cooldown.
  sig { returns(Integer) }
  def self.release_cooldown_days
    require "env_config"

    EnvConfig.release_cooldown_days
  end

  sig { returns(Integer) }
  def self.release_cooldown_seconds
    release_cooldown_days * 24 * 60 * 60
  end
end
