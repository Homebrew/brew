# frozen_string_literal: true

module Bundler
  module FetchMetadata
    # A fallback is included because the original version of the specification
    # API didn't include that field, so some marshalled specs in the index have it
    # set to +nil+.
    def matches_current_ruby?
      @required_ruby_version ||= _remote_specification.required_ruby_version || Gem::Requirement.default

      super
    end

    def matches_current_rubygems?
      # A fallback is included because the original version of the specification
      # API didn't include that field, so some marshalled specs in the index have it
      # set to +nil+.
      @required_rubygems_version ||= _remote_specification.required_rubygems_version || Gem::Requirement.default

      super
    end
  end

  module MatchRemoteMetadata
    include MatchMetadata

    prepend FetchMetadata
  end
end
