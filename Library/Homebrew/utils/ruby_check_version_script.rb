#!/usr/bin/env ruby
# typed: true
# frozen_string_literal: true

HOMEBREW_REQUIRED_RUBY_VERSION = ARGV.first.freeze
raise "No Ruby version passed!" if HOMEBREW_REQUIRED_RUBY_VERSION.to_s.empty?

require "rubygems"

ruby_version = Gem::Version.new(RUBY_VERSION)
homebrew_required_ruby_version = Gem::Version.new(HOMEBREW_REQUIRED_RUBY_VERSION)

ruby_version_major, ruby_version_minor, = ruby_version.canonical_segments
homebrew_required_ruby_version_major, homebrew_required_ruby_version_minor, =
  homebrew_required_ruby_version.canonical_segments

if (!ENV.fetch("HOMEBREW_DEVELOPER", "").empty? || !ENV.fetch("HOMEBREW_TESTS", "").empty?) &&
   !ENV.fetch("HOMEBREW_USE_RUBY_FROM_PATH", "").empty? &&
   ruby_version >= homebrew_required_ruby_version
  return
elsif ruby_version_major != homebrew_required_ruby_version_major ||
      ruby_version_minor != homebrew_required_ruby_version_minor
  abort
end
