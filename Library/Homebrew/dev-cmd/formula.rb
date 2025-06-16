# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"

module Homebrew
  module DevCmd
    class FormulaCmd < AbstractCommand
      cmd_args do
        description <<~EOS
          Display the path where <formula> is located.
        EOS

        named_args :formula, min: 1, without_api: true
      end

      sig { override.void }
      def run
        formula_paths = args.named.to_paths(only: :formula).select(&:exist?)
        if formula_paths.blank? && args.named
                                       .to_paths(only: :cask)
                                       .any?(&:exist?)
          odie "Found casks but did not find formulae!"
        end
        formula_paths.each { puts _1 }
      end
    end
  end
end
