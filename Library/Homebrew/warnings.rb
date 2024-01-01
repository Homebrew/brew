# typed: true
# frozen_string_literal: true

require "warning"

# Helper module for handling warnings.
#
# @api private
module Warnings
  COMMON_WARNINGS = {
    parser_syntax: [
      %r{warning: parser/current is loading parser/ruby\d+, which recognizes},
      /warning: \d+\.\d+\.\d+-compliant syntax, but you are running \d+\.\d+\.\d+\./,
      %r{warning: please see https://github\.com/whitequark/parser#compatibility-with-ruby-mri\.},
    ],
  }.freeze

  def self.ignore(*warnings)
    warnings.map! do |warning|
      next warning if !warning.is_a?(Symbol) || !COMMON_WARNINGS.key?(warning)

      COMMON_WARNINGS[warning]
    end

    warnings.flatten.each do |warning|
      Warning.ignore warning
    end
    return unless block_given?

    result = yield
    Warning.clear
    result
  end
end
