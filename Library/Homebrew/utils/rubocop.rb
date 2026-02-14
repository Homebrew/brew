#!/usr/bin/env ruby
# typed: strict
# frozen_string_literal: true

require_relative "../standalone"
require_relative "../warnings"

Warnings.ignore :parser_syntax do
  require "rubocop"
end

require "rubocop/test_prof"

exit RuboCop::CLI.new.run
