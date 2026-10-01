# typed: strict
# frozen_string_literal: true

require "vulns/cached_feed"
require "vulns/vulnerability"

module Homebrew
  module Vulns
    # Reader for the concatenated `BREW-*` OSV corpus generated from
    # Homebrew/advisory-database and published by formulae.brew.sh at
    # `/api/advisories.json`.
    #
    # Consumed by `brew generate-formula-api` to attach a `vulnerabilities`
    # field to each formula's API JSON, and by `brew vulns` (Phase 4) as the
    # local `ecosystem: Homebrew` range source until osv.dev ingests the feed.
    class AdvisoryDatabase < CachedFeed
      DATA_URL = "https://formulae.brew.sh/api/advisories.json"

      sig { override.returns(String) }
      def self.data_url = DATA_URL

      sig { override.returns(String) }
      def self.cache_filename = "advisories.json"

      sig { override.params(data: T.anything).void }
      def initialize(data)
        super
        raise Error, "advisory index is not a JSON object" unless (top = as_hash(data))
        raise Error, "advisory index has no 'advisories' key" unless top.key?("advisories")
        unless (advisories = as_hash(top["advisories"]))
          raise Error, "advisory index 'advisories' is not a JSON object"
        end

        @advisories = T.let(advisories, T::Hash[String, T.untyped])
        @meta = T.let(as_hash(top["meta"]) || {}, T::Hash[String, T.untyped])
      end

      sig { returns(T::Hash[String, T.untyped]) }
      attr_reader :meta

      sig { returns(T::Array[String]) }
      def formulae
        @advisories.keys
      end

      # {Vulnerability} wrappers for every `BREW-*` record whose
      # `affected[0].package.name` is `formula_name`.
      sig { params(formula_name: String).returns(T::Array[Vulnerability]) }
      def records_for(formula_name)
        Array(@advisories[formula_name]).filter_map do |record|
          Vulnerability.new(record) if record.is_a?(Hash)
        end
      end

      Entry = Struct.new(:id, :upstream, :summary, :severity, :fix, :fixed_in, keyword_init: true) do
        sig { returns(T::Hash[String, T.untyped]) }
        def to_api_hash
          to_h.transform_keys(&:to_s).compact
        end
      end

      # Evaluate every record for `formula_name` against `pkg_version` and
      # return the `{open:, patched:}` shape used by the formula API JSON and
      # `brew info`. `open` are records whose `ECOSYSTEM` range still contains
      # `pkg_version`; `patched` are records where `ecosystem_specific.fix` is
      # `"patch"` (Homebrew ships a `resolves`-annotated patch); `fixed_count`
      # counts bump-fixed records that no longer apply. Returns `nil` when the
      # corpus has no records for the formula so callers can distinguish
      # "checked, clean" from "not covered".
      sig {
        params(formula_name: String, pkg_version: T.any(String, PkgVersion))
          .returns(T.nilable(T::Hash[String, T.untyped]))
      }
      def status_for(formula_name, pkg_version)
        records = records_for(formula_name)
        return if records.empty?

        version = pkg_version.to_s
        open = T.let([], T::Array[Entry])
        patched = T.let([], T::Array[Entry])
        fixed_count = 0

        records.each do |vuln|
          eco = vuln.affected.first&.dig("ecosystem_specific") || {}
          status = vuln.range_status("Homebrew", formula_name, version)
          entry = Entry.new(
            id:       vuln.id,
            upstream: vuln.upstream.presence || vuln.aliases.presence,
            summary:  vuln.summary,
            severity: vuln.severity&.to_s,
            fix:      eco["fix"],
            fixed_in: status&.fixed_in,
          ).freeze
          case status&.state
          when nil, :affected then open << entry
          when :fixed
            if eco["fix"] == "patch"
              patched << entry
            else
              fixed_count += 1
            end
          when :not_applicable then next
          end
        end

        {
          "open"        => open.sort_by(&:id).map(&:to_api_hash),
          "patched"     => patched.sort_by(&:id).map(&:to_api_hash),
          "fixed_count" => fixed_count,
        }
      end
    end
  end
end
