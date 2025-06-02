# frozen_string_literal: true

# Use RubyGems vendored copy when available. Otherwise fallback to Bundler
# vendored copy. The vendored copy in Bundler can be removed once support for
# RubyGems 3.5.18 is dropped.

begin
  require "rubygems/vendored_securerandom"
rescue LoadError
  module Bundler::Random; end
  require_relative "vendor/securerandom/lib/securerandom"
  Gem::SecureRandom = Bundler::SecureRandom
  Gem::Random = Bundler::Random
end
