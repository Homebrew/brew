# typed: strict
# frozen_string_literal: true

require "cleanup"
require "cli/parser"

module Homebrew
  sig { returns(CLI::Parser) }
  def self.autoremove_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Uninstall formulae that were only installed as a dependency of another formula and are now no longer needed.
      EOS
      switch "-n", "--dry-run",
             description: "List what would be uninstalled, but do not actually uninstall anything."

      named_args :none
    end
  end

  sig { void }
  def self.autoremove
    args = autoremove_args.parse

    Cleanup.autoremove(dry_run: args.dry_run?)
  end
end
