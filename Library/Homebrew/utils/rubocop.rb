#!/usr/bin/env ruby
# typed: strict
# frozen_string_literal: true

require_relative "../standalone"
require_relative "../warnings"

Warnings.ignore :parser_syntax do
  require "rubocop"
end

# Load the test-prof RuboCop plugin manually to avoid issues with auto-loading (see test_prof_rubocop_stub.rb)
require_relative "test_prof_rubocop_stub"

exit RuboCop::CLI.new.run
