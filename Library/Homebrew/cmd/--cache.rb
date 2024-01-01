# typed: strict
# frozen_string_literal: true

require "fetch"
require "cli/parser"
require "cask/download"

module Homebrew
  extend Fetch

  sig { returns(CLI::Parser) }
  def self.__cache_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Display Homebrew's download cache. See also `HOMEBREW_CACHE`.

        If <formula> is provided, display the file or directory used to cache <formula>.
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
  end

  sig { void }
  def self.__cache
    args = __cache_args.parse

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
          SimulateSystem.with os: os, arch: arch do
            Formulary.clear_cache
            formula = Formulary.factory(ref)
            print_formula_cache(formula, os: os, arch: arch, args: args)
          end
        end
      else
        cask = formula_or_cask
        ref = cask.loaded_from_api? ? cask.full_name : cask.sourcefile_path

        os_arch_combinations.each do |os, arch|
          next if os == :linux

          SimulateSystem.with os: os, arch: arch do
            cask = Cask::CaskLoader.load(ref)
            print_cask_cache(cask)
          end
        end
      end
    end
  end

  sig { params(formula: Formula, os: Symbol, arch: Symbol, args: CLI::Args).void }
  def self.print_formula_cache(formula, os:, arch:, args:)
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
        Utils::Bottles::Tag.new(system: os, arch: arch)
      end

      bottle = formula.bottle_for_tag(bottle_tag)

      if bottle.nil?
        opoo "Bottle for tag #{bottle_tag.to_sym.inspect} is unavailable."
        return
      end

      puts bottle.cached_download
    elsif args.HEAD?
      puts T.must(formula.head).cached_download
    else
      puts formula.cached_download
    end
  end

  sig { params(cask: Cask::Cask).void }
  def self.print_cask_cache(cask)
    puts Cask::Download.new(cask).downloader.cached_location
  end
end
