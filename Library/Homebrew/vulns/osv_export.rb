# typed: strict
# frozen_string_literal: true

require "json"
require "fileutils"
require "vulns/osv"
require "vulns/scanner"

module Homebrew
  module Vulns
    # Emits OSV-schema records for the `Homebrew` ecosystem describing CVEs that
    # homebrew-core formulae resolve via shipped patches.
    #
    # One record is written per (formula, vulnerability id) pair found in
    # `serialized_patches[].resolves`. The record states that the formula was
    # affected up to (but not including) the currently shipped version+revision;
    # this is a "fixed at or before what we ship today" approximation, since the
    # precise fix boundary requires homebrew-core git archaeology.
    #
    # Record shape follows the OSV 1.7 schema and mirrors the Debian DSA layout
    # (`upstream` listing the source CVE, `affected[].ranges` of type
    # `ECOSYSTEM`, `ecosystem_specific` carrying the resolving patch detail).
    #
    # See {Homebrew::DevCmd::GenerateVulnsAdvisories} for the entry point and
    # https://github.com/Homebrew/advisory-database for the published
    # feed.
    module OsvExport
      # https://ossf.github.io/osv-schema/ — value of the emitted
      # `schema_version` field, pinning the OSV schema release these records
      # target. `Homebrew` and `BREW` were registered in that schema in
      # ossf/osv-schema#576.
      SCHEMA_VERSION = "1.7.3"
      ECOSYSTEM = "Homebrew"
      ID_PREFIX = "BREW"

      # `annotated` is a list of `[formula, serialized_patches]` pairs. The
      # patches are passed in rather than read from the formula so callers can
      # supply the union across OS/architecture variations (a `patch` inside an
      # `on_linux`/`on_intel` block only appears in `Formula#serialized_patches`
      # under the matching {SimulateSystem}).
      #
      # `first_fixed`, when given, is called `(formula, vuln_id) -> String?` for
      # records with no existing file to derive an accurate `fixed` boundary
      # (e.g. via {FormulaVersions} git history); existing records preserve
      # their on-disk `ranges` regardless.
      sig {
        params(annotated:   T::Array[[Formula, T::Array[T::Hash[String, T.untyped]]]],
               dir:         T.any(String, Pathname),
               first_fixed: T.nilable(T.proc.params(formula: Formula, vuln_id: String).returns(T.nilable(String))),
               now:         Time)
          .returns(T::Array[String])
      }
      def self.run(annotated, dir, first_fixed: nil, now: Time.now.utc)
        FileUtils.mkdir_p(dir)
        written = []
        upstream_cache = T.let({}, T::Hash[String, T.any(T::Hash[String, T.untyped], Symbol)])

        annotated.each do |formula, patches|
          Scanner.resolved_ids(patches).each do |vuln_id|
            upstream = upstream_cache.fetch(vuln_id) { upstream_cache[vuln_id] = fetch_upstream(vuln_id) }
            path = File.join(dir, "#{ID_PREFIX}-#{formula.name}-#{vuln_id}.json")
            existing = File.file?(path)
            # A transient OSV outage would otherwise strip summary/severity/etc.
            # from an existing enriched record; leave it untouched instead.
            next if upstream == :failed && existing

            fixed = (first_fixed&.call(formula, vuln_id) unless existing) || formula.pkg_version.to_s
            record = record_for(formula, vuln_id, patches:, fixed:,
                                upstream: upstream.is_a?(Hash) ? upstream : nil, now:)
            merged = merge_existing(path, record)
            next if merged.nil?

            File.write(path, "#{JSON.pretty_generate(merged)}\n")
            written << path
          end
        end

        written
      end

      # If a record already exists at `path`, carry forward its `published`
      # timestamp and `affected[].ranges` (so the `fixed` boundary reflects when
      # the annotation was first observed rather than drifting to today's
      # `pkg_version`), and skip the write entirely when nothing else has
      # changed. Records for annotations no longer in core are simply not
      # visited, so they persist.
      sig {
        params(path: String, record: T::Hash[Symbol, T.untyped]).returns(T.nilable(T::Hash[Symbol, T.untyped]))
      }
      def self.merge_existing(path, record)
        return record unless File.file?(path)

        existing = JSON.parse(File.read(path))
        # Records written before `published` was introduced only have
        # `modified`; use it as the migration value so `published` does not
        # jump forward to today on first rewrite.
        if (existing_published = existing["published"] || existing["modified"])
          record[:published] = existing_published
        end
        Array(record[:affected]).each_with_index do |affected, index|
          existing_ranges = existing.dig("affected", index, "ranges")
          affected[:ranges] = existing_ranges if existing_ranges
        end

        # Compare as parsed structures so key ordering (which JSON does not
        # define but Ruby serialisation preserves) does not cause spurious
        # rewrites of a hand-formatted or differently-serialised existing file.
        return if JSON.parse(JSON.generate(record)).except("modified") == existing.except("modified")

        record
      rescue JSON::ParserError
        record
      end

      sig {
        params(formula: Formula, vuln_id: String, patches: T::Array[T::Hash[String, T.untyped]],
               fixed: String, upstream: T.nilable(T::Hash[String, T.untyped]), now: Time)
          .returns(T::Hash[Symbol, T.untyped])
      }
      def self.record_for(formula, vuln_id, patches: formula.serialized_patches,
                          fixed: formula.pkg_version.to_s, upstream: nil, now: Time.now.utc)
        timestamp = now.strftime("%Y-%m-%dT%H:%M:%SZ")
        record = T.let({
          schema_version:    SCHEMA_VERSION,
          id:                "#{ID_PREFIX}-#{formula.name}-#{vuln_id}",
          published:         timestamp,
          modified:          timestamp,
          upstream:          [vuln_id],
          affected:          [affected_entry(formula, vuln_id, patches, fixed)],
          database_specific: { source: "generated" },
        }, T::Hash[Symbol, T.untyped])

        if upstream
          record[:summary] = upstream["summary"] if upstream["summary"]
          record[:details] = upstream["details"] if upstream["details"]
          record[:severity] = upstream["severity"] if upstream["severity"]
          record[:upstream] = ([vuln_id] + Array(upstream["aliases"])).uniq
          record[:references] = upstream["references"] if upstream["references"]
        end

        record
      end

      sig {
        params(formula: Formula, vuln_id: String, patches: T::Array[T::Hash[String, T.untyped]], fixed: String)
          .returns(T::Hash[Symbol, T.untyped])
      }
      def self.affected_entry(formula, vuln_id, patches, fixed)
        {
          package:            {
            ecosystem: ECOSYSTEM,
            name:      formula.name,
            purl:      purl(formula.name),
          },
          ranges:             [
            {
              type:   "ECOSYSTEM",
              events: [{ introduced: "0" }, { fixed: }],
            },
          ],
          ecosystem_specific: {
            fix:     "patch",
            patches: patches_resolving(patches, vuln_id).filter_map { |p| patch_ref(p) },
          },
        }
      end

      # Formula names use `[a-z0-9._+@-]`. Of those, `@` and `+` fall outside the
      # purl-spec unreserved set for the name component and must be
      # percent-encoded (`@` would otherwise be read as the name/version
      # separator; `+` is disallowed unencoded in a canonical purl name).
      PURL_NAME_ENCODE = T.let({ "@" => "%40", "+" => "%2B" }.freeze, T::Hash[String, String])
      private_constant :PURL_NAME_ENCODE

      sig { params(name: String).returns(String) }
      def self.purl(name)
        "pkg:brew/#{name.gsub(/[@+]/, PURL_NAME_ENCODE)}"
      end

      sig {
        params(serialized_patches: T::Array[T::Hash[String, T.untyped]], vuln_id: String)
          .returns(T::Array[T::Hash[String, T.untyped]])
      }
      def self.patches_resolving(serialized_patches, vuln_id)
        target = vuln_id.upcase
        serialized_patches.select do |p|
          Array(p["resolves"]).any? { |r| r.is_a?(Hash) && r["type"] == "security" && r["id"].to_s.upcase == target }
        end
      end

      PatchRef = T.type_alias { T::Hash[Symbol, T.any(String, T::Array[String])] }

      sig { params(patch: T::Hash[String, T.untyped]).returns(T.nilable(PatchRef)) }
      def self.patch_ref(patch)
        ref = T.let({}, PatchRef)
        ref[:type] = patch["type"] if patch["type"]
        ref[:url] = patch["url"] if patch["url"]
        ref[:file] = patch["file"] if patch["file"]
        ref[:apply] = patch["apply"] if patch["apply"]
        ref.presence
      end

      # Returns `:failed` (not `nil`) on error so callers can distinguish a
      # transient outage from a successful fetch that returned no enrichment.
      sig { params(vuln_id: String).returns(T.any(T::Hash[String, T.untyped], Symbol)) }
      def self.fetch_upstream(vuln_id)
        OSV.vulnerability(vuln_id)
      rescue OSV::Error
        :failed
      end
    end
  end
end
