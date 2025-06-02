# frozen_string_literal: true

module Bundler; end

# Use RubyGems vendored copy when available. Otherwise fallback to Bundler
# vendored copy. The vendored copy in Bundler can be removed once support for
# RubyGems 3.5 is dropped.

begin
  require "rubygems/vendor/uri/lib/uri"
rescue LoadError
  require_relative "vendor/uri/lib/uri"
  Gem::URI = Bundler::URI

  module Gem
    def URI(uri) # rubocop:disable Naming/MethodName
      Bundler::URI(uri)
    end
    module_function :URI
  end
end
