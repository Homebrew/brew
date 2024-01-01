# typed: true
# frozen_string_literal: true

require "json"
require "open3"
require "style"
require "cli/parser"

module Homebrew
  module_function

  sig { returns(CLI::Parser) }
  def style_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Check formulae or files for conformance to Homebrew style guidelines.

        Lists of <file>, <tap> and <formula> may not be combined. If none are
        provided, `style` will run style checks on the whole Homebrew library,
        including core code and all formulae.
      EOS
      switch "--fix",
             description: "Fix style violations automatically using RuboCop's auto-correct feature."
      switch "--display-cop-names",
             description: "Include the RuboCop cop name for each violation in the output.",
             hidden:      true
      switch "--reset-cache",
             description: "Reset the RuboCop cache."
      switch "--formula", "--formulae",
             description: "Treat all named arguments as formulae."
      switch "--cask", "--casks",
             description: "Treat all named arguments as casks."
      comma_array "--only-cops",
                  description: "Specify a comma-separated <cops> list to check for violations of only the " \
                               "listed RuboCop cops."
      comma_array "--except-cops",
                  description: "Specify a comma-separated <cops> list to skip checking for violations of the " \
                               "listed RuboCop cops."

      conflicts "--formula", "--cask"
      conflicts "--only-cops", "--except-cops"

      named_args [:file, :tap, :formula, :cask], without_api: true
    end
  end

  def style
    args = style_args.parse

    target = if args.no_named?
      nil
    else
      args.named.to_paths
    end

    only_cops = args.only_cops
    except_cops = args.except_cops

    options = {
      fix:         args.fix?,
      reset_cache: args.reset_cache?,
      debug:       args.debug?,
      verbose:     args.verbose?,
    }
    if only_cops
      options[:only_cops] = only_cops
    elsif except_cops
      options[:except_cops] = except_cops
    else
      options[:except_cops] = %w[FormulaAuditStrict]
    end

    Homebrew.failed = !Style.check_style_and_print(target, **options)
  end
end
