# typed: strict
# frozen_string_literal: true

require "json"
require "fileutils"
require "pkg_version"
require "uri"
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
      RANGE_EVENT_KEYS = %w[introduced fixed last_affected limit].freeze
      TERMINAL_EVENT_KEYS = %w[fixed last_affected limit].freeze
      private_constant :RANGE_EVENT_KEYS, :TERMINAL_EVENT_KEYS

      # `annotated` is a list of `[formula, serialized_patches]` pairs. The
      # patches are passed in rather than read from the formula so callers can
      # supply the union across OS/architecture variations (a `patch` inside an
      # `on_linux`/`on_intel` block only appears in `Formula#serialized_patches`
      # under the matching {SimulateSystem}).
      #
      # `first_fixed`, when given, is called `(formula, vuln_id) -> String?` for
      # records with no existing file to derive an accurate `fixed` boundary
      # (e.g. via {FormulaVersions} git history). It may return
      # `:history_unavailable` to skip a new record when no boundary can be
      # verified; existing records preserve their on-disk `ranges` regardless.
      sig {
        params(annotated:   T::Array[[Formula, T::Array[T::Hash[String, T.untyped]]]],
               dir:         T.any(String, Pathname),
               first_fixed: T.nilable(T.proc.params(formula: Formula, vuln_id: String)
                                         .returns(T.nilable(T.any(String, Symbol)))),
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
            path = File.join(dir, "#{record_id(formula, vuln_id)}.json")
            existing = File.file?(path)
            # A transient OSV outage would otherwise strip summary/severity/etc.
            # from an existing enriched record; leave it untouched instead.
            next if upstream == :failed && existing

            fixed_result = T.let(nil, T.nilable(T.any(String, Symbol)))
            fixed_result = first_fixed.call(formula, vuln_id) if first_fixed && !existing
            fixed = case fixed_result
            when String
              fixed_result
            when nil
              formula.pkg_version.to_s
            when :history_unavailable
              next
            else
              raise TypeError, "unexpected first-fixed result: #{fixed_result.inspect}"
            end
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
      # timestamp and `affected[].ranges` (so a terminal boundary does not
      # drift to today's `pkg_version`), and skip the write entirely when
      # nothing else has changed. `close_open_ranges` lets the matcher merge a
      # newly discovered `fixed` or reintroduced event into an existing range
      # while preserving its reviewed history. `initial_introduction` repairs
      # unreviewed ranges without reopening valid terminal ranges. Records for
      # annotations no longer in core are simply not visited, so they persist.
      sig {
        params(path: String, record: T::Hash[Symbol, T.untyped], close_open_ranges: T::Boolean,
               initial_introduction: T::Boolean)
          .returns(T.nilable(T::Hash[Symbol, T.untyped]))
      }
      def self.merge_existing(path, record, close_open_ranges: false, initial_introduction: false)
        return record unless File.file?(path)

        existing = JSON.parse(File.read(path))
        # Records written before `published` was introduced only have
        # `modified`; use it as the migration value so `published` does not
        # jump forward to today on first rewrite.
        if (existing_published = existing["published"] || existing["modified"])
          record[:published] = existing_published
        end
        affected_records = Array(record[:affected])
        invalid_transition = affected_records.each_with_index.any? do |affected, index|
          existing_ranges = existing.dig("affected", index, "ranges")
          next false unless existing_ranges

          close_open_ranges && (
            ((fixed = explicit_fixed(affected[:ranges])) && !fixed_follows?(existing_ranges, fixed)) ||
            (!initial_introduction && (introduced = explicit_reintroduction(affected[:ranges])) &&
              !reintroduction_follows?(existing_ranges, introduced))
          )
        end
        return if invalid_transition

        affected_records.each_with_index do |affected, index|
          existing_ranges = existing.dig("affected", index, "ranges")
          next unless existing_ranges

          affected[:ranges] = if close_open_ranges
            merge_range_transitions(existing_ranges, affected[:ranges], initial_introduction:)
          else
            existing_ranges
          end
        end

        # Compare as parsed structures so key ordering (which JSON does not
        # define but Ruby serialisation preserves) does not cause spurious
        # rewrites of a hand-formatted or differently-serialised existing file.
        return if JSON.parse(JSON.generate(record)).except("modified") == existing.except("modified")

        record
      rescue JSON::ParserError
        record
      end

      # True only when every range has a terminal `fixed`, `last_affected`, or
      # `limit` event. Invalid/empty ranges deliberately return false so the
      # selective matcher repairs them instead of treating them as reviewed.
      sig { params(ranges: T.untyped).returns(T::Boolean) }
      def self.ranges_terminal?(ranges)
        return false unless ranges.is_a?(Array)
        return false if ranges.empty?

        !!ranges.all? { |range| range_state(range) == :terminal }
      end

      sig { params(ranges: T.untyped).returns(T::Boolean) }
      def self.ranges_open?(ranges)
        return false unless ranges.is_a?(Array)
        return false if ranges.empty?

        states = ranges.map { |range| range_state(range) }
        states.exclude?(:invalid) && states.include?(:open)
      end

      # True when `fixed` can close every reviewed open Homebrew ecosystem
      # range. Terminal ranges are unchanged; invalid ranges remain eligible
      # for the existing repair path.
      sig { params(ranges: T.untyped, fixed: String).returns(T::Boolean) }
      def self.fixed_follows?(ranges, fixed)
        fixed_version = PkgVersion.parse(fixed)
        Array(ranges).all? do |range|
          next true unless range.is_a?(Hash)
          next true if (range["type"] || range[:type]) != "ECOSYSTEM"
          next true if range_state(range) != :open

          event = Array(range["events"] || range[:events]).rfind do |item|
            item.is_a?(Hash) && (item.key?("introduced") || item.key?(:introduced))
          end
          introduced = event&.[]("introduced") || event&.[](:introduced)
          introduced.is_a?(String) && fixed_version > PkgVersion.parse(introduced)
        rescue ArgumentError
          false
        end
      rescue ArgumentError
        false
      end

      # True when `introduced` is compatible with every reviewed Homebrew
      # ecosystem range. Open ranges are already affected and remain unchanged;
      # terminal ranges must end before the new boundary. Other OSV range types
      # (notably GIT commit ranges) are ignored.
      sig { params(ranges: T.untyped, introduced: String).returns(T::Boolean) }
      def self.reintroduction_follows?(ranges, introduced)
        ecosystem_ranges = Array(ranges).select do |range|
          range.is_a?(Hash) && (range["type"] || range[:type]) == "ECOSYSTEM"
        end
        return false if ecosystem_ranges.empty?

        introduced_version = PkgVersion.parse(introduced)
        ecosystem_ranges.all? do |range|
          state = range_state(range)
          next true if state == :open
          next false if state != :terminal

          terminal = terminal_event(range)
          next false unless terminal

          terminal_key = TERMINAL_EVENT_KEYS.find do |key|
            terminal.key?(key) || terminal.key?(key.to_sym)
          end
          next false unless terminal_key

          terminal_version = terminal[terminal_key] || terminal[terminal_key.to_sym]
          next false unless terminal_version.is_a?(String)

          terminal_version = PkgVersion.parse(terminal_version)
          if terminal_key == "limit"
            introduced_version >= terminal_version
          else
            introduced_version > terminal_version
          end
        rescue ArgumentError
          false
        end
      rescue ArgumentError
        false
      end

      sig {
        params(existing_ranges: T.untyped, incoming_ranges: T.untyped, initial_introduction: T::Boolean).returns(T.untyped)
      }
      def self.merge_range_transitions(existing_ranges, incoming_ranges, initial_introduction:)
        return incoming_ranges if !existing_ranges.is_a?(Array) || existing_ranges.empty?

        incoming_ranges = Array(incoming_ranges)
        fixed = incoming_ranges.filter_map do |range|
          Array(range[:events] || range["events"]).rfind do |event|
            event.is_a?(Hash) && (event.key?(:fixed) || event.key?("fixed"))
          end
        end.first
        fixed_version = fixed&.[](:fixed) || fixed&.[]("fixed")
        introduced = incoming_ranges.filter_map do |range|
          Array(range[:events] || range["events"]).rfind do |event|
            next false unless event.is_a?(Hash)

            value = event[:introduced] || event["introduced"]
            value && value != "0"
          end
        end.first
        introduced_version = introduced&.[](:introduced) || introduced&.[]("introduced")
        has_invalid = existing_ranges.any? { |range| range_state(range) == :invalid }
        return existing_ranges if fixed_version.nil? && introduced_version.nil? && !has_invalid

        existing_ranges.map.with_index do |range, index|
          case range_state(range)
          when :invalid
            replacement = incoming_ranges[index] || incoming_ranges.first
            next range unless replacement

            if range.is_a?(Hash)
              events = replacement[:events] || replacement["events"]
              range.merge("events" => events)
            else
              replacement
            end
          when :open
            next range unless fixed_version
            next range if (range["type"] || range[:type]) != "ECOSYSTEM"

            events = Array(range["events"])
            last_event_index = events.rindex do |event|
              event.is_a?(Hash) && RANGE_EVENT_KEYS.any? do |key|
                event.key?(key) || event.key?(key.to_sym)
              end
            end
            last_event = events[last_event_index] if last_event_index
            if last_event && (last_event["limit"] || last_event[:limit]) == "*"
              events = events.dup
              events[last_event_index] = { "fixed" => fixed_version }
            else
              events << { "fixed" => fixed_version }
            end
            range.merge("events" => events)
          when :terminal
            next range if initial_introduction
            next range unless introduced_version
            next range if (range["type"] || range[:type]) != "ECOSYSTEM"

            events = Array(range["events"])
            range.merge("events" => [*events, { "introduced" => introduced_version }])
          else
            range
          end
        end
      end
      private_class_method :merge_range_transitions

      sig { params(range: T.untyped).returns(Symbol) }
      def self.range_state(range)
        return :invalid unless range.is_a?(Hash)

        events = range["events"] || range[:events]
        return :invalid if !events.is_a?(Array) || events.empty?

        last = events.rfind do |event|
          event.is_a?(Hash) && RANGE_EVENT_KEYS.any? do |key|
            event.key?(key) || event.key?(key.to_sym)
          end
        end
        return :invalid unless last

        limit = last["limit"] || last[:limit]
        return :open if limit == "*"

        (last.key?("introduced") || last.key?(:introduced)) ? :open : :terminal
      end
      private_class_method :range_state

      sig { params(range: T.untyped).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
      def self.terminal_event(range)
        return unless range.is_a?(Hash)

        Array(range["events"] || range[:events]).rfind do |event|
          event.is_a?(Hash) && TERMINAL_EVENT_KEYS.any? do |key|
            event.key?(key) || event.key?(key.to_sym)
          end
        end
      end
      private_class_method :terminal_event

      sig { params(ranges: T.untyped).returns(T.nilable(String)) }
      def self.explicit_reintroduction(ranges)
        event = Array(ranges).filter_map do |range|
          Array(range[:events] || range["events"]).rfind do |event|
            next false unless event.is_a?(Hash)

            value = event[:introduced] || event["introduced"]
            value && value != "0"
          end
        end.first
        event && (event[:introduced] || event["introduced"])
      end
      private_class_method :explicit_reintroduction

      sig { params(ranges: T.untyped).returns(T.nilable(String)) }
      def self.explicit_fixed(ranges)
        event = Array(ranges).filter_map do |range|
          Array(range[:events] || range["events"]).rfind do |item|
            item.is_a?(Hash) && (item.key?(:fixed) || item.key?("fixed"))
          end
        end.first
        event && (event[:fixed] || event["fixed"])
      end
      private_class_method :explicit_fixed

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
          id:                record_id(formula, vuln_id),
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
          if (refs = upstream["references"])
            # OSV.dev merges NVD and cve.org reference lists without normalising
            # percent-encoding, so the same URL can appear twice (e.g. `%40` vs
            # `@`). Collapse those while keeping the same URL under distinct
            # `type` values, which the schema allows and which carries meaning.
            record[:references] = refs.uniq do |r|
              [r["type"], URI::RFC2396_PARSER.unescape(r["url"].to_s)]
            end
          end
        end

        record
      end

      sig { params(formula: Formula, vuln_id: String).returns(String) }
      def self.record_id(formula, vuln_id)
        "#{ID_PREFIX}-#{formula.name}-#{vuln_id}"
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
