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

exit RuboCop::CLI.new.run
