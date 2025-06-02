# frozen_string_literal: true

module Bundler
  module ForcePlatform
    # The `:force_ruby_platform` value used by dependencies for resolution, and
    # by locked specifications for materialization is `false` by default, except
    # for TruffleRuby. TruffleRuby generally needs to force the RUBY platform
    # variant unless the name is explicitly allowlisted.

    def default_force_ruby_platform
      return false unless RUBY_ENGINE == "truffleruby"

      !Gem::Platform::REUSE_AS_BINARY_ON_TRUFFLERUBY.include?(name)
    end
  end
end
