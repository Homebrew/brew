# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"
require "formulary"
require "json"

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
        db_path = Pathname(args.output_db) if args.output_db
        args.named.each { |name| process(name, db_path:) }
      end

      private

      sig { params(name: String, db_path: T.nilable(Pathname)).void }
      def process(name, db_path:)
        formula = Formulary.factory(name)
        line = db_line(formula)
        if db_path
          write_db(db_path, formula.full_name, line)
        elsif line
          puts line
        end
      rescue FormulaUnavailableError
        write_db(db_path, name, nil) if db_path&.exist?
      end

      sig { params(db_path: Pathname, name: String, line: T.nilable(String)).void }
      def write_db(db_path, name, line)
        lines = db_path.readlines(chomp: true).reject(&:blank?) if db_path.exist?
        lines = (lines || []).filter_map { |l| l unless l.start_with?("#{name}(") }
        lines << line if line
        db_path.write("#{lines.sort.join("\n")}\n")
      end

      sig { params(formula: Formula).returns(T.nilable(String)) }
      def db_line(formula)
        return if formula.disabled? || formula.deprecated?

        exes = executables_from_manifest(formula)
        "#{formula.full_name}(#{formula.pkg_version}):#{exes.join(" ")}"
      end

      sig { params(formula: Formula).returns(T::Array[String]) }
      def executables_from_manifest(formula)
        return [] unless formula.bottled?

        manifest_path = HOMEBREW_CACHE.glob("#{formula.name}_bottle_manifest--*").first
        if manifest_path.blank?
          bottle = formula.bottle
          return [] unless bottle

          bottle.fetch
          manifest_path = HOMEBREW_CACHE.glob("#{formula.name}_bottle_manifest--*").first
        end
        return [] if manifest_path.blank?

        manifest = JSON.parse(T.must(manifest_path).read)
        exec_files = manifest.dig("manifests", 0, "annotations", "sh.brew.path_exec_files")
        return [] if exec_files.blank?

        exec_files.split.map { |f| File.basename(f) }.sort
      rescue JSON::ParserError => e
        opoo "Failed to parse bottle manifest for #{formula.name}: #{e.message}"
        []
      end
    end
  end
end
