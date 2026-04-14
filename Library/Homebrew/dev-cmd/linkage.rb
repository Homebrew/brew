# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "cache_store"
require "linkage_checker"

module Homebrew
  module DevCmd
    class Linkage < AbstractCommand
      cmd_args do
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
               description: "Print the cached linkage values stored in `$HOMEBREW_CACHE`, set by a previous " \
                            "`brew linkage` run."

        named_args :installed_formula
      end

      sig { override.void }
      def run
        CacheStoreDatabase.use(:linkage) do |db|
          kegs = if args.named.to_default_kegs.empty?
            Formula.installed.filter_map(&:any_installed_keg)
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
  end
end
