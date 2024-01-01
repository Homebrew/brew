# typed: true
# frozen_string_literal: true

require "formula"
require "options"

module Homebrew
  module_function

  sig { returns(CLI::Parser) }
  def options_args
    Homebrew::CLI::Parser.new do
      description <<~EOS
        Show install options specific to <formula>.
      EOS
      switch "--compact",
             description: "Show all options on a single line separated by spaces."
      switch "--installed",
             description: "Show options for formulae that are currently installed."
      switch "--eval-all",
             description: "Evaluate all available formulae and casks, whether installed or not, to show their " \
                          "options."
      flag   "--command=",
             description: "Show options for the specified <command>."

      conflicts "--installed", "--all", "--command"

      named_args :formula
    end
  end

  def options
    args = options_args.parse

    all = args.eval_all?

    if all
      puts_options Formula.all(eval_all: args.eval_all?).sort, args: args
    elsif args.installed?
      puts_options Formula.installed.sort, args: args
    elsif args.command.present?
      cmd_options = Commands.command_options(args.command)
      odie "Unknown command: #{args.command}" if cmd_options.nil?

      if args.compact?
        puts cmd_options.sort.map(&:first) * " "
      else
        cmd_options.sort.each { |option, desc| puts "#{option}\n\t#{desc}" }
        puts
      end
    elsif args.no_named?
      raise FormulaUnspecifiedError
    else
      puts_options args.named.to_formulae, args: args
    end
  end

  def puts_options(formulae, args:)
    formulae.each do |f|
      next if f.options.empty?

      if args.compact?
        puts f.options.as_flags.sort * " "
      else
        puts f.full_name if formulae.length > 1
        Options.dump_for_formula f
        puts
      end
    end
  end
end
