#!/usr/bin/env ruby
# typed: strict
# frozen_string_literal: true

require_relative "../standalone"
require_relative "../warnings"

Warnings.ignore :parser_syntax do
  require "rubocop"
end

# TODO: Remove this workaround once TestProf fixes their RuboCop plugin.
require_relative "test_prof_rubocop_stub"

exit RuboCop::CLI.new.run
