#!/usr/bin/env ruby
# typed: strict
# frozen_string_literal: true

require_relative "../standalone"
require_relative "../warnings"

# The standalone bundle is generated on macOS, so activate the installed platform-specific Rubydex gem.
rubydex_spec = begin
  Gem::Specification.find_by_name("rubydex")
rescue Gem::MissingSpecError
  nil
end
if rubydex_spec&.full_require_paths&.none? { |path| $LOAD_PATH.include?(path) }
  rubydex_spec.activate
end

Warnings.ignore :parser_syntax do
  require "rubocop"
end

# Dir.pwd resolves the tap symlink created by setup-homebrew. Keep the installed
# path for the index so it matches the files RuboCop inspects under Library/Taps.
if ARGV in ["--tap-root", tap_root, *]
  ARGV.shift(2)
  RuboCop::PathUtil.define_singleton_method(:pwd) { tap_root }
end

exit RuboCop::CLI.new.run
