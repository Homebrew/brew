# frozen_string_literal: true

module Bundler
  module MatchMetadata
    def matches_current_ruby?
      @required_ruby_version.satisfied_by?(Gem.ruby_version)
    end

    def matches_current_rubygems?
      @required_rubygems_version.satisfied_by?(Gem.rubygems_version)
    end
  end
end
