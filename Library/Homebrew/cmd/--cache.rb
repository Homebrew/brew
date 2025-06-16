# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "fetch"
require "cask/download"

module Homebrew
  module Cmd
    class Cache < AbstractCommand
      include Fetch

      sig { override.returns(String) }
      def self.command_name = "--cache"

      cmd_args do
        description <<~EOS
          Display Homebrew's download cache. See also `$HOMEBREW_CACHE`.

          If a <formula> or <cask> is provided, display the file or directory used to cache it.
        EOS
        flag   "--os=",
               description: "Show cache file for the given operating system. " \
                            "(Pass `all` to show cache files for all operating systems.)"
        flag   "--arch=",
               description: "Show cache file for the given CPU architecture. " \
                            "(Pass `all` to show cache files for all architectures.)"
        switch "-s", "--build-from-source",
               description: "Show the cache file used when building from source."
        switch "--force-bottle",
               description: "Show the cache file used when pouring a bottle."
        flag "--bottle-tag=",
             description: "Show the cache file used when pouring a bottle for the given tag."
        switch "--HEAD",
               description: "Show the cache file used when building from HEAD."
        switch "--formula", "--formulae",
               description: "Only show cache files for formulae."
        switch "--cask", "--casks",
               description: "Only show cache files for casks."

        conflicts "--build-from-source", "--force-bottle", "--bottle-tag", "--HEAD", "--cask"
        conflicts "--formula", "--cask"
        conflicts "--os", "--bottle-tag"
        conflicts "--arch", "--bottle-tag"

        named_args [:formula, :cask]
      end

      sig { override.void }
      def run
        if args.no_named?
          puts HOMEBREW_CACHE
          return
        end

        formulae_or_casks = args.named.to_formulae_and_casks
        os_arch_combinations = args.os_arch_combinations

        formulae_or_casks.each do |formula_or_cask|
          case formula_or_cask
          when Formula
            formula = formula_or_cask
            ref = formula.loaded_from_api? ? formula.full_name : formula.path

            os_arch_combinations.each do |os, arch|
              SimulateSystem.with(os:, arch:) do
                formula = Formulary.factory(ref)
                print_formula_cache(formula, os:, arch:)
              end
            end
          when Cask::Cask
            cask = formula_or_cask
            ref = cask.loaded_from_api? ? cask.full_name : cask.sourcefile_path

            os_arch_combinations.each do |os, arch|
              next if os == :linux

              SimulateSystem.with(os:, arch:) do
                loaded_cask = Cask::CaskLoader.load(ref)
                print_cask_cache(loaded_cask)
              end
            end
          else
            raise "Invalid type: #{formula_or_cask.class}"
          end
        end
      end

      private

      sig { params(formula: Formula, os: Symbol, arch: Symbol).void }
      def print_formula_cache(formula, os:, arch:)
        if fetch_bottle?(
          formula,
          force_bottle:               args.force_bottle?,
          bottle_tag:                 args.bottle_tag&.to_sym,
          build_from_source_formulae: args.build_from_source_formulae,
          os:                         args.os&.to_sym,
          arch:                       args.arch&.to_sym,
        )
          bottle_tag = if (bottle_tag = args.bottle_tag&.to_sym)
            Utils::Bottles::Tag.from_symbol(bottle_tag)
          else
            Utils::Bottles::Tag.new(system: os, arch:)
          end

          bottle = formula.bottle_for_tag(bottle_tag)

          if bottle.nil?
            opoo "Bottle for tag #{bottle_tag.to_sym.inspect} is unavailable."
            return
          end

          puts bottle.cached_download
        elsif args.HEAD?
          if (head = formula.head)
            puts head.cached_download
          else
            opoo "No head is defined for #{formula.full_name}."
          end
        else
          puts formula.cached_download
        end
      end

      sig { params(cask: Cask::Cask).void }
      def print_cask_cache(cask)
        puts Cask::Download.new(cask).downloader.cached_location
      end
    end
  end
end
