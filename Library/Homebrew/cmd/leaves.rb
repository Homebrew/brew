# typed: true
# frozen_string_literal: true

require "formula"
require "cask_dependent"
require "cli/parser"

module Homebrew
  module_function

  sig { returns(CLI::Parser) }
  def leaves_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        List installed formulae that are not dependencies of another installed formula or cask.
      EOS
      switch "-r", "--installed-on-request",
             description: "Only list leaves that were manually installed."
      switch "-p", "--installed-as-dependency",
             description: "Only list leaves that were installed as dependencies."

      conflicts "--installed-on-request", "--installed-as-dependency"

      named_args :none
    end
  end

  def installed_on_request?(formula)
    Tab.for_keg(formula.any_installed_keg).installed_on_request
  end

  def installed_as_dependency?(formula)
    Tab.for_keg(formula.any_installed_keg).installed_as_dependency
  end

  def leaves
    args = leaves_args.parse

    leaves_list = Formula.installed - Formula.installed.flat_map(&:runtime_formula_dependencies)
    casks_runtime_dependencies = Cask::Caskroom.casks.flat_map do |cask|
      CaskDependent.new(cask).runtime_dependencies.map(&:to_formula)
    end
    leaves_list -= casks_runtime_dependencies
    leaves_list.select!(&method(:installed_on_request?)) if args.installed_on_request?
    leaves_list.select!(&method(:installed_as_dependency?)) if args.installed_as_dependency?

    leaves_list.map(&:full_name)
               .sort
               .each(&method(:puts))
  end
end
