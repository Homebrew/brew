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
          existing = db_path.exist? ? db_path.readlines(chomp: true).reject(&:empty?) : []
          lines = existing.reject { |l| l.start_with?("#{formula.full_name}(") }
          lines << line if line
          db_path.write("#{lines.sort.join("\n")}\n")
        else
          puts line if line
        end
      rescue FormulaUnavailableError
        return unless db_path&.exist?

        lines = db_path.readlines(chomp: true).reject { |l| l.start_with?("#{name}(") }
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
