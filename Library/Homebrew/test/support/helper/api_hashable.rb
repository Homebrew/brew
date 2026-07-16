# typed: strict
# frozen_string_literal: true

require "api_hashable"

# `generating_hash!` monkeypatches global state for API generation. The commands
# that generate the API exit once they are done, so only tests need to revert it.
module APIHashable
  sig { void }
  def generated_hash!
    return unless generating_hash?

    Object.send(:remove_const, :HOMEBREW_PREFIX)
    Object.const_set(:HOMEBREW_PREFIX, @old_homebrew_prefix)
    ENV["HOME"] = @old_home
    ENV["GIT_CONFIG_GLOBAL"] = @old_git_config_global

    @generating_hash = false
  end
end
