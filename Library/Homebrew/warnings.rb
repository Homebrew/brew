# typed: strict
# frozen_string_literal: true

require "warning"

# Helper module for handling warnings.
module Warnings
  COMMON_WARNINGS = T.let({
    parser_syntax: [
      %r{warning: parser/current is loading parser/ruby\d+, which recognizes},
      /warning: \d+\.\d+\.\d+-compliant syntax, but you are running \d+\.\d+\.\d+\./,
      %r{warning: please see https://github\.com/whitequark/parser#compatibility-with-ruby-mri\.},
    ],
  }.freeze, T::Hash[Symbol, T::Array[Regexp]])

  sig { params(warnings: T.any(Symbol, Regexp), _block: T.nilable(T.proc.void)).void }
  def self.ignore(*warnings, &_block)
    warnings.map! do |warning|
      next warning if !warning.is_a?(Symbol) || !COMMON_WARNINGS.key?(warning)

      COMMON_WARNINGS[warning]
    end

    warnings.flatten.each do |warning|
      Warning.ignore warning
    end
    return unless block_given?

    yield
    Warning.clear
  end
end
