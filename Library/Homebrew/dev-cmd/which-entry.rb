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
        db_path = args.output_db&.then { |path| Pathname(path) }
        args.named.each { |name| process(name, db_path:) }
      end

      private

      sig { params(name: String, db_path: T.nilable(Pathname)).void }
      def process(name, db_path:)
        formula = Formulary.factory(name)
        line = db_line(formula)
        if db_path
          upsert_entry(db_path, formula.full_name, line)
        else
          puts line if line
        end
      rescue FormulaUnavailableError
        remove_entry(db_path, name) if db_path
      end

      sig { params(formula: Formula).returns(T.nilable(String)) }
      def db_line(formula)
        return if formula.disabled? || formula.deprecated?

        "#{formula.full_name}(#{formula.pkg_version}):#{executables_from_manifest(formula).join(" ")}"
      end

      sig { params(formula: Formula).returns(T::Array[String]) }
      def executables_from_manifest(formula)
        return [] unless formula.bottled?

        manifest_path = cached_manifest(formula) || fetch_manifest(formula)
        return [] unless manifest_path

        manifest = JSON.parse(manifest_path.read)
        exec_files = manifest.dig("manifests", 0, "annotations", "sh.brew.path_exec_files")
        return [] if exec_files.blank?

        exec_files.split.map { |f| File.basename(f) }.sort
      rescue JSON::ParserError
        []
      end

      sig { params(formula: Formula).returns(T.nilable(Pathname)) }
      def cached_manifest(formula)
        HOMEBREW_CACHE.glob("#{formula.name}_bottle_manifest--*").first
      end

      sig { params(formula: Formula).returns(T.nilable(Pathname)) }
      def fetch_manifest(formula)
        return unless (bottle = formula.bottle)

        bottle.fetch
        cached_manifest(formula)
      end

      sig { params(db_path: Pathname).returns(T::Array[String]) }
      def read_db(db_path)
        return [] unless db_path.exist?

        db_path.readlines(chomp: true).reject(&:empty?)
      end

      sig { params(db_path: Pathname, name: String, line: T.nilable(String)).void }
      def upsert_entry(db_path, name, line)
        lines = read_db(db_path).reject { |l| l.start_with?("#{name}(") }
        lines << line if line
        db_path.write("#{lines.sort.join("\n")}\n")
      end

      sig { params(db_path: T.nilable(Pathname), name: String).void }
      def remove_entry(db_path, name)
        return unless db_path

        upsert_entry(db_path, name, nil)
      end
    end
  end
end
