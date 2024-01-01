# typed: true
# frozen_string_literal: true

require "cli/parser"
require "formula"

module Homebrew
  module_function

  sig { returns(CLI::Parser) }
  def home_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Open a <formula> or <cask>'s homepage in a browser, or open
        Homebrew's own homepage if no argument is provided.
      EOS
      switch "--formula", "--formulae",
             description: "Treat all named arguments as formulae."
      switch "--cask", "--casks",
             description: "Treat all named arguments as casks."

      conflicts "--formula", "--cask"

      named_args [:formula, :cask]
    end
  end

  sig { void }
  def home
    args = home_args.parse

    if args.no_named?
      exec_browser HOMEBREW_WWW
      return
    end

    # to_formulae_and_casks is typed to possibly return Kegs (but won't without explicitly asking)
    formulae_or_casks = T.cast(args.named.to_formulae_and_casks, T::Array[T.any(Formula, Cask::Cask)])
    homepages = formulae_or_casks.map do |formula_or_cask|
      puts "Opening homepage for #{name_of(formula_or_cask)}"
      formula_or_cask.homepage
    end

    exec_browser(*T.unsafe(homepages))
  end

  def name_of(formula_or_cask)
    if formula_or_cask.is_a? Formula
      "Formula #{formula_or_cask.name}"
    else
      "Cask #{formula_or_cask.token}"
    end
  end
end
