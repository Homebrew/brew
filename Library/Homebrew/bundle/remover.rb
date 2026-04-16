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

        entry_regex = /#{entry_type}(\s+|\(\s*)"(#{escaped_args.join("|")})"/
        new_lines = T.let([], T::Array[String])

        content.split("\n").compact.each do |line|
          if line.match?(entry_regex)
            name = line[entry_regex, 2]
            remove_package_description_comment(new_lines, T.must(name))
          else
            new_lines << line
          end
        end

        new_content = "#{new_lines.join("\n")}\n"

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
        formula = find_formula_or_cask(formula_name, raise_error:)
        return [] if formula.nil? || !formula.is_a?(Formula)

        [formula_name, formula.name, formula.full_name, *formula.aliases, *formula.oldnames].compact.uniq
      end

      sig { params(lines: T::Array[String], package_name: String).void }
      def self.remove_package_description_comment(lines, package_name)
        comment = lines.last&.match(/^\s*#\s+(?<desc>.+)$/)&.[](:desc)
        return unless comment
        return if find_formula_or_cask(package_name)&.desc != comment

        lines.pop
      end

      sig { params(name: String, raise_error: T::Boolean).returns(T.nilable(T.any(Formula, ::Cask::Cask))) }
      def self.find_formula_or_cask(name, raise_error: false)
        formula = begin
          Formulary.factory(name)
        rescue FormulaUnavailableError
          raise if raise_error
        end

        return formula if formula.present?

        begin
          ::Cask::CaskLoader.load(name)
        rescue ::Cask::CaskUnavailableError
          raise if raise_error
        end
      end
    end
  end
end
