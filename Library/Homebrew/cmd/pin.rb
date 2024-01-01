# typed: true
# frozen_string_literal: true

require "formula"
require "cli/parser"

module Homebrew
  module_function

  sig { returns(CLI::Parser) }
  def pin_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Pin the specified <formula>, preventing them from being upgraded when
        issuing the `brew upgrade` <formula> command. See also `unpin`.

        Note: Other packages which depend on newer versions of a pinned formula
        might not install or run correctly.
      EOS

      named_args :installed_formula, min: 1
    end
  end

  def pin
    args = pin_args.parse

    args.named.to_resolved_formulae.each do |f|
      if f.pinned?
        opoo "#{f.name} already pinned"
      elsif !f.pinnable?
        onoe "#{f.name} not installed"
      else
        f.pin
      end
    end
  end
end
