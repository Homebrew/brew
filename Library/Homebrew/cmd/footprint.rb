# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"
require "keg"
require "tab"

module Homebrew
  module Cmd
    class Footprint < AbstractCommand
      cmd_args do
        description <<~EOS
          Show the true disk cost of installed formulae, including exclusive
          dependencies that would be freed on uninstall.

          When given formula arguments, show the footprint of each.
          With `--installed`, show all top-level (explicitly requested) formulae
          ranked by total footprint.
        EOS

        switch "--installed",
               description: "Show all installed formulae ranked by total disk footprint."
        switch "--all",
               depends_on:  "--installed",
               description: "Include formulae installed as dependencies, not just those installed on request."
        flag   "--json",
               description: "Print a JSON representation of the footprint data."

        named_args :installed_formula
      end

      sig { override.void }
      def run
        if args.installed?
          run_installed
        elsif args.no_named?
          raise UsageError, "must specify formulae or use `--installed`."
        else
          run_named
        end
      end

      private

      sig { void }
      def run_installed; end

      sig { void }
      def run_named; end
    end
  end
end
