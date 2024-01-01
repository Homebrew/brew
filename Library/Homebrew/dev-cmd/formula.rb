# typed: true
# frozen_string_literal: true

require "formula"
require "cli/parser"

module Homebrew
  module_function

  sig { returns(CLI::Parser) }
  def formula_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Display the path where <formula> is located.
      EOS

      named_args :formula, min: 1, without_api: true
    end
  end

  def formula
    args = formula_args.parse

    formula_paths = args.named.to_paths(only: :formula).select(&:exist?)
    if formula_paths.blank? && args.named
                                   .to_paths(only: :cask)
                                   .any?(&:exist?)
      odie "Found casks but did not find formulae!"
    end
    formula_paths.each(&method(:puts))
  end
end
