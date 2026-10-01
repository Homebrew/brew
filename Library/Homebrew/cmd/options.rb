# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"
require "options"

module Homebrew
  module Cmd
    class OptionsCmd < AbstractCommand
      cmd_args do
        description <<~EOS
          Show install options specific to <formula>.
        EOS
        switch "--compact",
               description: "Show all options on a single line separated by spaces."
        switch "--installed",
               description: "Show options for formulae that are currently installed."
        switch "--eval-all",
               description: "Evaluate all available formulae and casks, whether installed or not, to show their " \
                            "options.",
               env:         :eval_all,
               replacement: "the default trusted-tap behaviour",
               odisabled:   true
        flag   "--command=",
               description: "Show options for the specified <command>.",
               odisabled:   true

        conflicts "--command", "--installed", "--eval-all"

        named_args :formula
      end

      sig { override.void }
      def run
        if args.no_named?
          puts_options(Formula.all.sort)
        elsif args.installed?
          puts_options(Formula.installed.sort)
        else
          puts_options args.named.to_formulae
        end
      end

      private

      sig { params(formulae: T::Array[Formula]).void }
      def puts_options(formulae)
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
  end
end
