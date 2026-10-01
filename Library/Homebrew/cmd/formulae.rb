# typed: strict
# frozen_string_literal: true

require "abstract_command"

module Homebrew
  module Cmd
    class Formulae < AbstractCommand
      # Used when the Bash implementation falls back to Ruby for tap trust filtering.
      cmd_args do
        description "List all locally installable formulae including short names."
      end

      sig { override.void }
      def run
        require "formula"

        puts Formula.all.flat_map { |formula| [formula.full_name, formula.name] }.uniq.sort
      end
    end
  end
end
