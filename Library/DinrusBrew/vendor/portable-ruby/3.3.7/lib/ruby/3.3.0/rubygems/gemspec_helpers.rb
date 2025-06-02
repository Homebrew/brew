# frozen_string_literal: true

require_relative "../rubygems"

##
# Mixin methods for commands that work with gemspecs.

module Gem::GemspecHelpers
  def find_gemspec(glob = "*.gemspec")
    gemspecs = Dir.glob(glob).sort

    if gemspecs.size > 1
      alert_error "Multiple gemspecs found: #{gemspecs}, please specify one"
      terminate_interaction(1)
    end

    gemspecs.first
  end
end
