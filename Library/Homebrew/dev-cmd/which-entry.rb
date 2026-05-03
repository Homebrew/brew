# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"
require "formulary"

module Homebrew
  module DevCmd
    class WhichEntry < AbstractCommand
      cmd_args do
        description <<~EOS
          Generate an `executables.txt` entry for <formula> using bottle manifest metadata.
        EOS
        flag "--output-db=",
             description: "Append or update the entry in the given `executables.txt` database file."
        named_args :formula, min: 1
      end

      sig { override.void }
      def run
        db_path = args.output_db
        raise UsageError, "`--output-db` is required." unless db_path

        args.named.to_formulae.each { |formula| process(formula, db_path: Pathname(db_path)) }
      end

      private

      sig { params(formula: Formula, db_path: Pathname).void }
      def process(formula, db_path:)
        line = db_line(formula)
        write_db(db_path, formula.full_name, line)
      end

      sig { params(db_path: Pathname, name: String, line: T.nilable(String)).void }
      def write_db(db_path, name, line)
        lines = db_path.readlines(chomp: true).compact_blank if db_path.exist?
        # TODO: remove once pkg_versions are no longer in executables.txt
        lines = Array(lines).reject { |l| l.start_with?(/#{Regexp.escape(name)}(?:\(.+\))?:/) }
        lines << line if line
        db_path.write("#{lines.sort.join("\n")}\n")
      end

      sig { params(formula: Formula).returns(T.nilable(String)) }
      def db_line(formula)
        return if formula.disabled? || formula.deprecated?

        exes = executables_from_manifest(formula)
        "#{formula.full_name}:#{exes.join(" ")}"
      end

      sig { params(formula: Formula).returns(T::Array[String]) }
      def executables_from_manifest(formula)
        manifest_resource = formula.bottle&.github_packages_manifest_resource
        return [] unless manifest_resource

        manifest_resource.fetch unless manifest_resource.downloaded?
        manifest_path = manifest_resource.cached_download
        return [] unless manifest_path.exist?

        manifest_resource.path_exec_files
      rescue JSON::ParserError => e
        opoo "Failed to parse bottle manifest for #{formula.name}: #{e.message}"
        []
      end
    end
  end
end
