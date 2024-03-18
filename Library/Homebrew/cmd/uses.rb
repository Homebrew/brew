# typed: true
# frozen_string_literal: true

# `brew uses foo bar` returns formulae that use both foo and bar
# If you want the union, run the command twice and concatenate the results.
# The intersection is harder to achieve with shell tools.

require "formula"
require "cli/parser"
require "cask/caskroom"
require "dependencies_helpers"
require "ostruct"

module Homebrew
  extend DependenciesHelpers

  sig { returns(CLI::Parser) }
  def self.uses_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Show formulae and casks that specify <formula> as a dependency; that is, show dependents
        of <formula>. When given multiple formula arguments, show the intersection
        of formulae that use <formula>. By default, `uses` shows all formulae and casks that
        specify <formula> as a required or recommended dependency for their stable builds.

        *Note:* `--missing` and `--skip-recommended` have precedence over `--include-*`.
      EOS
      switch "--recursive",
             description: "Resolve more than one level of dependencies."
      switch "--installed",
             description: "Only list formulae and casks that are currently installed."
      switch "--missing",
             description: "Only list formulae and casks that are not currently installed."
      switch "--eval-all",
             description: "Evaluate all available formulae and casks, whether installed or not, to show " \
                          "their dependents."
      switch "--include-build",
             description: "Include formulae that specify <formula> as a `:build` dependency."
      switch "--include-test",
             description: "Include formulae that specify <formula> as a `:test` dependency."
      switch "--include-optional",
             description: "Include formulae that specify <formula> as an `:optional` dependency."
      switch "--skip-recommended",
             description: "Skip all formulae that specify <formula> as a `:recommended` dependency."
      switch "--formula", "--formulae",
             description: "Include only formulae."
      switch "--cask", "--casks",
             description: "Include only casks."

      conflicts "--formula", "--cask"
      conflicts "--installed", "--all"
      conflicts "--missing", "--installed"

      named_args :formula, min: 1
    end
  end

  def self.uses
    args = uses_args.parse

    Formulary.enable_factory_cache!

    used_formulae_missing = false
    used_formulae = begin
      args.named.to_formulae
    rescue FormulaUnavailableError => e
      opoo e
      used_formulae_missing = true
      # If the formula doesn't exist: fake the needed formula object name.
      # This is a legacy use of OpenStruct that should be refactored.
      # rubocop:disable Style/OpenStructUse
      args.named.map { |name| OpenStruct.new name:, full_name: name }
      # rubocop:enable Style/OpenStructUse
    end

    use_runtime_dependents = args.installed? &&
                             !used_formulae_missing &&
                             !args.include_build? &&
                             !args.include_test? &&
                             !args.include_optional? &&
                             !args.skip_recommended?

    uses = intersection_of_dependents(use_runtime_dependents, used_formulae, args:)

    return if uses.empty?

    puts Formatter.columns(uses.map(&:full_name).sort)
    odie "Missing formulae should not have dependents!" if used_formulae_missing
  end

  def self.intersection_of_dependents(use_runtime_dependents, used_formulae, args:)
    recursive = args.recursive?
    show_formulae_and_casks = !args.formula? && !args.cask?
    includes, ignores = args_includes_ignores(args)

    deps = []
    if use_runtime_dependents
      if show_formulae_and_casks || args.formula?
        deps += used_formulae.map(&:runtime_installed_formula_dependents)
                             .reduce(&:&)
                             .select(&:any_version_installed?)
      end
      if show_formulae_and_casks || args.cask?
        deps += select_used_dependents(
          dependents(Cask::Caskroom.casks),
          used_formulae, recursive, includes, ignores
        )
      end

      deps
    else
      all = args.eval_all?

      if !args.installed? && !(all || Homebrew::EnvConfig.eval_all?)
        raise UsageError, "`brew uses` needs `--installed` or `--eval-all` passed or `HOMEBREW_EVAL_ALL` set!"
      end

      if show_formulae_and_casks || args.formula?
        deps += args.installed? ? Formula.installed : Formula.all(eval_all: args.eval_all?)
      end
      if show_formulae_and_casks || args.cask?
        deps += args.installed? ? Cask::Caskroom.casks : Cask::Cask.all(eval_all: args.eval_all?)
      end

      if args.missing?
        deps.reject! do |dep|
          case dep
          when Formula
            dep.any_version_installed?
          when Cask::Cask
            dep.installed?
          end
        end
        ignores.delete(:satisfied?)
      end

      select_used_dependents(dependents(deps), used_formulae, recursive, includes, ignores)
    end
  end

  def self.select_used_dependents(dependents, used_formulae, recursive, includes, ignores)
    dependents.select do |d|
      deps = if recursive
        recursive_includes(Dependency, d, includes, ignores)
      else
        select_includes(d.deps, ignores, includes)
      end

      used_formulae.all? do |ff|
        deps.any? do |dep|
          match = begin
            dep.to_formula.full_name == ff.full_name if dep.name.include?("/")
          rescue
            nil
          end
          next match unless match.nil?

          dep.name == ff.name
        end
      rescue FormulaUnavailableError
        # Silently ignore this case as we don't care about things used in
        # taps that aren't currently tapped.
        next
      end
    end
  end
end
