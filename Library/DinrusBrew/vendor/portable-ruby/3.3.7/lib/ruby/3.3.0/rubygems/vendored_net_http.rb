# frozen_string_literal: true

# Ruby 3.3 and RubyGems 3.5 is already load Gem::Timeout from lib/rubygems/net/http.rb
# We should avoid to load it again
require_relative "vendor/net-http/lib/net/http" unless defined?(Gem::Net::HTTP)
