# frozen_string_literal: true

# This defined? guard can be removed once RubyGems 3.4 support is dropped.
#
# Bundler specs load this code from `spec/support/vendored_net_http.rb` to avoid
# activating the Bundler gem too early. Without this guard, we get redefinition
# warnings once Bundler is actually activated and
# `lib/bundler/vendored_net_http.rb` is required. This is not an issue in
# RubyGems versions including `rubygems/vendored_net_http` since `require` takes
# care of avoiding the double load.
#
unless defined?(Gem::Net)
  begin
    require "rubygems/vendored_net_http"
  rescue LoadError
    begin
      require "rubygems/net/http"
    rescue LoadError
      require "net/http"
      Gem::Net = Net
    end
  end
end
