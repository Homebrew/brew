# frozen_string_literal: true

# Ruby 3.3 and RubyGems 3.5 is already load Gem::Timeout from lib/rubygems/timeout.rb
# We should avoid to load it again
require_relative "vendor/timeout/lib/timeout" unless defined?(Gem::Timeout)
