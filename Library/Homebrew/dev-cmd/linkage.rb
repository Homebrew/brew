# typed: true
# frozen_string_literal: true

require "cache_store"
require "linkage_checker"
require "cli/parser"

module Homebrew
  module_function

  sig { returns(CLI::Parser) }
  def linkage_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Check the library links from the given <formula> kegs. If no <formula> are
        provided, check all kegs. Raises an error if run on uninstalled formulae.
      EOS
      switch "--test",
             description: "Show only missing libraries and exit with a non-zero status if any missing " \
                          "libraries are found."
      switch "--strict",
             depends_on:  "--test",
             description: "Exit with a non-zero status if any undeclared dependencies with linkage are found."
      switch "--reverse",
             description: "For every library that a keg references, print its dylib path followed by the " \
                          "binaries that link to it."
      switch "--cached",
             description: "Print the cached linkage values stored in `HOMEBREW_CACHE`, set by a previous " \
                          "`brew linkage` run."

      named_args :installed_formula
    end
  end

  def linkage
    args = linkage_args.parse

    CacheStoreDatabase.use(:linkage) do |db|
      kegs = if args.named.to_default_kegs.empty?
        Formula.installed.map(&:any_installed_keg).compact
      else
        args.named.to_default_kegs
      end
      kegs.each do |keg|
        ohai "Checking #{keg.name} linkage" if kegs.size > 1

        result = LinkageChecker.new(keg, cache_db: db)

        if args.test?
          result.display_test_output(strict: args.strict?)
          Homebrew.failed = true if result.broken_library_linkage?(test: true, strict: args.strict?)
        elsif args.reverse?
          result.display_reverse_output
        else
          result.display_normal_output
        end
      end
    end
  end
end
