# typed: strict
# frozen_string_literal: true

require "utils/output"

module Homebrew
  module Bundle
    module Remover
      extend ::Utils::Output::Mixin

      sig { params(args: String, type: Symbol, global: T::Boolean, file: T.nilable(String)).void }
      def self.remove(*args, type:, global:, file:)
        require "bundle/brewfile"
        require "bundle/dumper"

        brewfile = Brewfile.read(global:, file:)
        content = brewfile.input
        entry_type = type.to_s if type != :none
        escaped_args = args.flat_map do |arg|
          names = if type == :brew
            possible_names(arg)
          else
            [arg]
          end

          names.uniq.map { |a| Regexp.escape(a) }
        end

        new_content = content.split("\n")
                             .grep_v(/#{entry_type}(\s+|\(\s*)"(#{escaped_args.join("|")})"/)
                             .join("\n") << "\n"

        if content.chomp == new_content.chomp &&
           type == :none &&
           args.any? { |arg| possible_names(arg, raise_error: false).count > 1 }
          opoo "No matching entries found in Brewfile. Try again with `--formula` to match formula " \
               "aliases and old formula names."
          return
        end

        path = Dumper.brewfile_path(global:, file:)
        Dumper.write_file path, new_content
      end

      sig { params(formula_name: String, raise_error: T::Boolean).returns(T::Array[String]) }
      def self.possible_names(formula_name, raise_error: true)
        formula = Formulary.factory(formula_name)
        [formula_name, formula.name, formula.full_name, *formula.aliases, *formula.oldnames].compact.uniq
      rescue FormulaUnavailableError
        raise if raise_error

        []
      end
    end
  end
end
