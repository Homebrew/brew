# typed: true
# frozen_string_literal: true

require "migrator"
require "cli/parser"
require "cask/migrator"

module Homebrew
  sig { returns(CLI::Parser) }
  def self.migrate_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Migrate renamed packages to new names, where <formula> are old names of
        packages.
      EOS
      switch "-f", "--force",
             description: "Treat installed <formula> and provided <formula> as if they are from " \
                          "the same taps and migrate them anyway."
      switch "-n", "--dry-run",
             description: "Show what would be migrated, but do not actually migrate anything."
      switch "--formula", "--formulae",
             description: "Only migrate formulae."
      switch "--cask", "--casks",
             description: "Only migrate casks."

      conflicts "--formula", "--cask"

      named_args [:installed_formula, :installed_cask], min: 1
    end
  end

  def self.migrate
    args = migrate_args.parse

    args.named.to_formulae_and_casks(warn: false).each do |formula_or_cask|
      case formula_or_cask
      when Formula
        Migrator.migrate_if_needed(formula_or_cask, force: args.force?, dry_run: args.dry_run?)
      when Cask::Cask
        Cask::Migrator.migrate_if_needed(formula_or_cask, dry_run: args.dry_run?)
      end
    end
  end
end
