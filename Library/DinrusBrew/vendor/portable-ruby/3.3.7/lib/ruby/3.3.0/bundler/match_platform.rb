# frozen_string_literal: true

require_relative "gem_helpers"

module Bundler
  module MatchPlatform
    include GemHelpers

    def match_platform(p)
      MatchPlatform.platforms_match?(platform, p)
    end

    def self.platforms_match?(gemspec_platform, local_platform)
      return true if gemspec_platform.nil?
      return true if gemspec_platform == Gem::Platform::RUBY
      return true if local_platform == gemspec_platform
      gemspec_platform = Gem::Platform.new(gemspec_platform)
      return true if gemspec_platform === local_platform

      false
    end
  end
end
