# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "fileutils"
require "json"

module Homebrew
  module DevCmd
    class GenerateAdvisoriesApi < AbstractCommand
      cmd_args do
        description <<~EOS
          Generate advisory API data for <#{HOMEBREW_API_WWW}> from a checkout of
          <https://github.com/Homebrew/advisory-database>.
          The generated file is written to the current directory.
        EOS

        named_args :directory, number: 1

        hide_from_man_page!
      end

      sig { override.void }
      def run
        repository = Pathname(args.named.fetch(0))
        result = build(repository/"advisories")
        FileUtils.mkdir_p "api"
        File.write("api/advisories.json", "#{JSON.generate(result)}\n")
      end

      private

      # Kept in step with AdvisoryIndex in Homebrew/advisory-database.
      sig { params(directory: Pathname).returns(T::Hash[String, T.untyped]) }
      def build(directory)
        raise "#{directory} is not a directory" unless directory.directory?

        paths = directory.glob("*.json").sort
        # An empty result here means a bad checkout or path, not an empty
        # corpus; publishing it would wipe the client view of every advisory.
        raise "no advisory records found in #{directory}" if paths.empty?

        by_formula = T.let({}, T::Hash[String, T::Array[T::Hash[String, T.untyped]]])
        schema_versions = T.let([], T::Array[T.nilable(String)])
        skipped_uncomparable = 0

        paths.each do |path|
          record = parse(path)
          formula_name = record.dig("affected", 0, "package", "name")
          raise "#{path}: missing affected[0].package.name" unless formula_name.is_a?(String)

          schema_versions << record["schema_version"]
          if actionable?(record)
            (by_formula[formula_name] ||= []) << record
          else
            skipped_uncomparable += 1
          end
        end

        versions = schema_versions.compact.uniq
        if versions.size > 1
          raise "mixed schema_version across advisories: #{versions.sort.inspect}"
        end

        {
          "meta"       => {
            "count"                => by_formula.each_value.sum(&:size),
            "skipped_uncomparable" => skipped_uncomparable,
            "schema_version"       => versions.first,
          },
          "advisories" => by_formula.transform_values { |records| records.sort_by { |record| record.fetch("id") } }
                                    .sort.to_h,
        }
      end

      sig { params(path: Pathname).returns(T::Hash[String, T.untyped]) }
      def parse(path)
        JSON.parse(path.read)
      rescue JSON::ParserError => e
        raise "#{path}: #{e.message}"
      end

      sig { params(record: T::Hash[String, T.untyped]).returns(T::Boolean) }
      def actionable?(record)
        database_specific = record["database_specific"] || {}
        return true if database_specific["source"] != "matched"

        Array(record["affected"]).any? do |affected|
          affected.dig("ecosystem_specific", "range_state")
        end
      end
    end
  end
end
