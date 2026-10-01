# typed: strict
# frozen_string_literal: true

require "api/env"
require "utils/output"

require "abstract_command"
require "extend/object/deep_dup"
require "fileutils"
require "formula"
require "vulns/match"

module Homebrew
  module DevCmd
    class AdvisoryMatch < AbstractCommand
      cmd_args do
        description <<~EOS
          Match <formula> against OSV.dev (GIT, language-registry and distro
          ecosystems) and CPANSA to produce candidate `BREW-*` advisory records
          for <https://github.com/Homebrew/advisory-database>.

          This is authoring-time tooling for the advisory-database CI and the
          `homebrew-core` PR bot; use `brew vulns` to scan installed formulae.
        EOS
        switch "--all",
               description: "Match every formula in `homebrew/core`."
        switch "--index",
               description: "Emit the formula-identity index as JSON and exit."
        switch "--json",
               description: "Output candidate records as a JSON array."
        flag   "--output=",
               description: "Write each record to <directory> as " \
                            "`BREW-<formula>-<id>.json`, preserving existing " \
                            "`published`/`ranges` fields."
        flag   "--repology=",
               description: "Load the formula to distro-package index from " \
                            "<file> instead of the published `data/repology.json`."
        flag   "--overrides=",
               description: "Load reviewed formula and advisory matching overrides from <file>."
        switch "--no-history",
               description: "Skip `FormulaVersions` walks for new ranges; use " \
                            "zero/current `pkg_version` as unverified boundaries."
        switch "--new-history",
               depends_on:  "--output=",
               description: "Skip `FormulaVersions` for existing terminal ranges " \
                            "unless their matching provenance changes."
        switch "--reconcile-history",
               depends_on:  "--output=",
               description: "Reconcile existing matched terminal ranges against complete history; " \
                            "requires `--overrides`."
        flag   "--formula-list=",
               description: "Match only the core formula names in a newline-separated file with " \
                            "`--new-history` or `--reconcile-history`, using bulk queries."
        conflicts "--formula-list", "--all"
        conflicts "--reconcile-history", "--new-history"
        conflicts "--reconcile-history", "--no-history"
        conflicts "--reconcile-history", "--json"
        conflicts "--reconcile-history", "--index"
        conflicts "--all", "--index"
        conflicts "--all", "--json"
        conflicts "--index", "--json"
        conflicts "--index", "--output"
        conflicts "--no-history", "--new-history"

        named_args [:formula]

        hide_from_man_page!
      end

      sig { override.void }
      def run
        if args.formula_list && !args.reconcile_history? && !args.new_history?
          raise UsageError, "`--formula-list` requires `--new-history` or `--reconcile-history`"
        end
        if args.reconcile_history? && !args.overrides
          raise UsageError, "`--reconcile-history` requires an explicit `--overrides` file"
        end
        if args.formula_list && args.named.any?
          raise UsageError, "`--formula-list` does not take named arguments"
        end

        formula_names = if (list = args.formula_list)
          File.readlines(list, chomp: true).reject(&:empty?).uniq
        end
        Formulary.enable_factory_cache!
        Homebrew::API.with_no_api_env do
          latest_macos = MacOSVersion.new((HOMEBREW_MACOS_NEWEST_UNSUPPORTED.to_i - 1).to_s).to_sym
          Homebrew::SimulateSystem.with(os: latest_macos, arch: :arm) do
            overrides = local_overrides
            matcher = Homebrew::Vulns::Match.new(repology:        local_repology,
                                                 overrides:,
                                                 bulk:            args.all? || args.index? || !formula_names.nil?,
                                                 strict_upstream: args.reconcile_history?)
            next emit_index(matcher) if args.index?

            emitter = build_emitter(formula_names:)
            begin
              on_error = if args.reconcile_history?
                lambda do |formula, error|
                  hold_upstream_formula(formula, error, emitter)
                end
              end
              matcher.each_advisory_batch(
                each_formula(formula_names:),
                on_error:,
              ) do |formula, hits|
                if args.reconcile_history? && emitter.is_a?(DirEmitter)
                  reconcile_formula(matcher, formula, hits, emitter, latest_macos:)
                  next
                end

                report(matcher, formula, hits) if text_mode?
                # A below-introduced hit would otherwise look open to OSV
                # consumers; it must not participate in alias maintenance.
                actionable = hits.filter_map do |hit|
                  status, = matcher.range_status(hit, formula_name: formula.name)
                  [hit, status] if status&.state != :not_applicable
                end
                record_ids_by_canonical = actionable.to_h do |hit, _status|
                  ids = matcher.record_ids(formula, hit)
                  [ids.fetch(0), ids]
                end
                alias_errors = emitter.prepare_aliases(formula.name, record_ids_by_canonical)
                if alias_errors.any?
                  alias_errors.each { |error| onoe error }
                  Homebrew.failed = true
                  next
                end

                actionable.each do |hit, status|
                  record_id = matcher.record_id(formula, hit)
                  next if emitter.alias_protected?(record_id)

                  reviewed_state = emitter.reviewed_range_state(record_id)
                  if reviewed_state && !status && matcher.current_prerelease_boundary?(hit)
                    opoo "#{record_id}: prerelease_boundary in current version; leaving reviewed record unchanged"
                    next
                  end
                  initial_introduction = false
                  initial_introduction = true if !args.no_history? && status && reviewed_state.nil?
                  candidate = matcher.to_brew_record(formula, hit)
                  basis_changed = emitter.range_basis_changed?(candidate)
                  if basis_changed && !initial_introduction && (args.no_history? || !status&.fixed?)
                    emitter.emit(candidate)
                    next
                  end

                  override = overrides&.advisory_override(formula.name, hit.identifiers)
                  if initial_introduction && override&.state
                    upstream_state = matcher.aggregate_state_at(formula, hit)
                    if override.state != upstream_state
                      emitter.record_history_unavailable(formula.name)
                      opoo "#{record_id}: reviewed state override " \
                           "#{upstream_state.nil? ? "cannot be checked against" : "disagrees with"} " \
                           "upstream history; " \
                           "skipping automatic update. Review its ranges and provenance together."
                      next
                    end
                  end

                  has_open_range = reviewed_state == :open
                  has_terminal_range = reviewed_state == :terminal
                  transition = (status&.fixed? && has_open_range) ||
                               (status&.affected? && has_terminal_range)
                  if args.no_history? && transition
                    opoo "#{record_id}: reviewed range transition needs history; leaving it unchanged"
                    next
                  end

                  walk_history = !args.no_history? && status&.fixed?
                  walk_history &&= basis_changed || emitter.history_required?(record_id) if args.new_history?
                  emitter.record_history_walk if walk_history
                  first_fixed = matcher.first_fixed_version(formula, hit) if walk_history
                  fixed_boundary = T.let(nil, T.nilable(String))
                  case first_fixed
                  when String
                    fixed_boundary = first_fixed
                  when nil
                    # No history walk was required.
                  when :never_affected
                    next
                  when :history_unavailable
                    emitter.record_history_unavailable(formula.name)
                    opoo "#{record_id}: formula history is unavailable; skipping automatic update"
                    next
                  else
                    raise TypeError, "unexpected fixed-history result: #{first_fixed.inspect}"
                  end

                  if fixed_boundary && !emitter.fixed_boundary_valid?(record_id, fixed_boundary)
                    onoe "#{record_id}: fixed #{fixed_boundary} does not follow its reviewed range"
                    Homebrew.failed = true
                    next
                  end

                  first_introduced = T.let(nil, T.nilable(String))
                  if initial_introduction
                    emitter.record_history_walk
                    introduced = matcher.first_introduced_version(formula, hit, first_fixed: fixed_boundary)
                    case introduced
                    when String
                      first_introduced = introduced
                    when :history_unavailable
                      emitter.record_history_unavailable(formula.name)
                      opoo "#{record_id}: affected introduction cannot be established; skipping automatic update"
                      next
                    else
                      raise TypeError, "unexpected introduction-history result: #{introduced.inspect}"
                    end
                  end
                  if status&.affected? && has_terminal_range
                    emitter.record_history_walk
                    reintroduced = matcher.first_reintroduced_version(formula, hit)
                    if reintroduced == :history_unavailable
                      emitter.record_history_unavailable(formula.name)
                      opoo "#{record_id}: reintroduction history is unavailable; skipping automatic update"
                      next
                    end
                    unless reintroduced.is_a?(String)
                      onoe "#{record_id}: could not find a prior non-affected version for its reviewed fixed range"
                      Homebrew.failed = true
                      next
                    end
                    unless emitter.reintroduction_boundary_valid?(record_id, reintroduced)
                      onoe "#{record_id}: reintroduction #{reintroduced} does not follow its reviewed range"
                      Homebrew.failed = true
                      next
                    end
                    first_introduced = reintroduced
                  end

                  candidate = matcher.to_brew_record(formula, hit, first_fixed: fixed_boundary, first_introduced:)
                  # A metadata override does not replace the upstream constraints
                  # used by the history walk. Correct its reviewed ranges and
                  # provenance together instead of automatically certifying them.
                  revalidated = !fixed_boundary.nil? && !override&.fixed_in_overridden
                  emitter.emit(candidate, revalidated:, initial_introduction:)
                end
              end
            rescue Homebrew::Vulns::OSV::Error => e
              onoe "OSV query failed: #{e.message}"
              Homebrew.failed = true
            end
            emitter.finish
            report_history_load_failures(matcher) if args.reconcile_history?
          end
        end
      end

      sig { params(matcher: Homebrew::Vulns::Match).void }
      def report_history_load_failures(matcher)
        failures = matcher.history_load_failures
        return if failures.empty?

        revisions = failures.map { |failure| [failure.formula, failure.revision, failure.path] }.uniq.length
        formulae = failures.map(&:formula).uniq.length
        puts "  History loads: #{revisions} failed formula revisions across #{formulae} formulae " \
             "(#{failures.length} platform loads)"
        return unless args.verbose?

        failures.each do |failure|
          puts "    #{failure.formula}: #{failure.revision}:#{failure.path} [#{failure.platform}] " \
               "#{failure.error_class}: #{failure.message}"
        end
      end

      sig {
        params(matcher: Homebrew::Vulns::Match, formula: Formula,
               hits: T::Array[Homebrew::Vulns::Match::Hit], emitter: DirEmitter, latest_macos: Symbol).void
      }
      def reconcile_formula(matcher, formula, hits, emitter, latest_macos:)
        return if matcher.skip_formula?(formula.name)

        resource_records = emitter.reconciliation_resource_records(formula.name).reject do |record|
          if hits.any? { |hit| record.upstream.intersect?(hit.identifiers) }
            true
          elsif matcher.preserve_homebrew_ranges?(formula.name, record.upstream)
            emitter.skip_reconciliation(record.id, [:preserved])
            true
          else
            false
          end
        end
        resource_hits = matcher.resource_advisories_for(resource_records)
        hits = matcher.dedup_by_aliases(hits + resource_hits)
        resource_records.each do |record|
          next if hits.any? { |hit| record.upstream.intersect?(hit.identifiers) }

          emitter.skip_reconciliation(record.id, [:resource_not_rediscovered])
        end
        groups = hits.to_h do |hit|
          ids = matcher.record_ids(formula, hit)
          [ids.fetch(0), ids]
        end
        errors = emitter.prepare_aliases(formula.name, groups)
        if errors.any?
          errors.each { |error| onoe error }
          Homebrew.failed = true
          return
        end

        candidates = hits.to_h { |hit| [matcher.record_id(formula, hit), matcher.to_brew_record(formula, hit)] }
        candidates.select! { |_, record| emitter.reconciliation_record(record) }
        return if candidates.empty?

        outcomes = T.let({}, T::Hash[String, T::Array[Homebrew::Vulns::Match::ReconciledHistory]])
        candidates.each_key { |id| outcomes[id] = [] }
        platforms = T.let([[latest_macos, :arm], [latest_macos, :intel], [:linux, :arm], [:linux, :intel]],
                          T::Array[[Symbol, Symbol]])
        platforms.each_with_index do |(os, arch), index|
          pending = candidates.select do |id, _|
            outcomes.fetch(id).all? { |result| [:range, :never_affected].include?(result.state) }
          end
          break if pending.empty?

          Homebrew::SimulateSystem.with(os:, arch:) do
            # Reload under each platform: resources and primary sources can differ.
            begin
              view = index.zero? ? formula : Formulary.factory(formula.path)
              platform_hits = if index.zero?
                hits
              else
                matcher.dedup_by_aliases(
                  matcher.advisories_for(view) + resource_hits,
                )
              end
            rescue Homebrew::Vulns::OSV::Error
              raise
            rescue => e
              pending.each_key do |id|
                outcomes.fetch(id) << Homebrew::Vulns::Match::ReconciledHistory.new(
                  state: :unresolved, introduced: nil, fixed: nil, reasons: [:platform_unavailable],
                )
              end
              opoo "#{formula.name} (#{os}/#{arch}): #{e.message}"
              next
            end
            pending.each do |id, record|
              family = platform_hits.select { |hit| hit.identifiers.intersect?(record.fetch(:upstream)) }
              if platform_provenance_changed?(matcher, emitter, record, view, family)
                result = Homebrew::Vulns::Match::ReconciledHistory.new(
                  state: :unresolved, introduced: nil, fixed: nil, reasons: [:platform_provenance_changed],
                )
              else
                hit = family.fetch(0)
                result = if resource_records.any? { |stored| stored.upstream.intersect?(hit.identifiers) }
                  matcher.reconcile_history(view, hit, require_resource_presence: true)
                else
                  matcher.reconcile_history(view, hit)
                end
                emitter.record_history_walk if result.state != :preserved
              end
              outcomes.fetch(id) << result
            end
          end
        end
        candidates.each do |id, record|
          results = outcomes.fetch(id)
          reasons = results.flat_map(&:reasons)
          reasons << :preserved if results.any? { |result| result.state == :preserved }
          decisions = results.map { |result| [result.state, result.introduced, result.fixed] }.uniq
          if reasons.empty? && (results.length != platforms.length || !decisions.one?)
            reasons << :platform_disagreement
          end
          if reasons.any?
            emitter.skip_reconciliation(id, reasons.uniq)
          else
            emitter.reconcile(record, results.fetch(0))
          end
        end
      rescue Homebrew::Vulns::OSV::Error => e
        hold_upstream_formula(formula, e, emitter)
      end

      # A platform view must rediscover the record through exactly one hit
      # carrying its stored upstream family with the same matching provenance;
      # anything else means the stored ranges cannot be compared across views.
      sig {
        params(matcher: Homebrew::Vulns::Match, emitter: DirEmitter, record: T::Hash[Symbol, T.untyped],
               view: Formula, family: T::Array[Homebrew::Vulns::Match::Hit]).returns(T::Boolean)
      }
      def platform_provenance_changed?(matcher, emitter, record, view, family)
        hit = family.first
        return true if !family.one? || hit.nil?
        return true if emitter.range_basis(record) != emitter.range_basis(matcher.to_brew_record(view, hit))

        (record.fetch(:upstream) - hit.identifiers).any?
      end

      sig { params(formula: Formula, error: Homebrew::Vulns::OSV::Error, emitter: Emitter).void }
      def hold_upstream_formula(formula, error, emitter)
        emitter.record_upstream_unavailable(formula.name) if emitter.is_a?(DirEmitter)
        opoo "#{formula.name}: upstream unavailable; leaving its records unchanged: #{error.message}"
      end

      # A CI run that has just built the index locally (advisory-database's
      # Ingest) reads it directly instead of fetching the published copy.
      sig { returns(T.nilable(Homebrew::Vulns::Repology)) }
      def local_repology
        return unless (path = args.repology)

        Homebrew::Vulns::Repology.from_file(Pathname(path))
      end

      sig { returns(T.nilable(Homebrew::Vulns::AdvisoryOverrides)) }
      def local_overrides
        return unless (path = args.overrides)

        Homebrew::Vulns::AdvisoryOverrides.from_file(Pathname(path))
      end

      sig { params(formula_names: T.nilable(T::Array[String])).returns(T::Enumerator[Formula]) }
      def each_formula(formula_names: nil)
        return args.named.to_resolved_formulae.each if !args.all? && !args.formula_list

        raise UsageError, "`--all` does not take named arguments" if args.named.any?

        tap = CoreTap.instance
        raise TapUnavailableError, tap.name unless tap.installed?

        names = tap.formula_names
        if formula_names
          (formula_names - names).each do |name|
            opoo "#{name}: no longer in homebrew/core; leaving its records unchanged"
          end
          names &= formula_names
        end

        Enumerator.new do |y|
          names.each do |name|
            y << Formulary.factory(name)
          rescue => e
            onoe "Error loading formula '#{name}': #{e}"
          end
        end
      end

      sig { returns(T::Boolean) }
      def text_mode?
        !args.json? && args.output.nil?
      end

      sig {
        params(matcher: Homebrew::Vulns::Match, formula: Formula,
               hits: T::Array[Homebrew::Vulns::Match::Hit]).void
      }
      def report(matcher, formula, hits)
        ohai "#{formula.name} #{formula.pkg_version}"
        if hits.empty?
          puts "  No advisories matched."
          return
        end
        hits.sort_by { |h| [-h.vulnerability.severity_level, h.canonical_id] }.each do |hit|
          v = hit.vulnerability
          status, = matcher.range_status(hit, formula_name: formula.name)
          state = case status&.state
          when nil       then "uncomparable"
          when :affected then "AFFECTED#{", upstream fix #{status&.fixed_in}" if status&.fixed_in}"
          when :fixed    then "fixed (upstream #{status&.fixed_in || "?"})"
          else "not applicable"
          end
          summary = v.summary&.slice(0, 60)
          puts "  #{hit.canonical_id} [#{hit.strategy}, #{matcher.confidence_for(hit, status)}] " \
               "#{v.severity_display} #{state}" \
               "#{" (resource: #{hit.resource})" if hit.resource}" \
               "#{" — #{summary}" if summary}"
        end
      end

      # `--output` and text mode write per-record and only accumulate counts;
      # `--json` accumulates the array (single-formula / PR-bot use, so bounded).
      class Emitter
        sig { params(_formula_name: String, _groups: T::Hash[String, T::Array[String]]).returns(T::Array[String]) }
        def prepare_aliases(_formula_name, _groups) = []

        sig { params(_record_id: String).returns(T::Boolean) }
        def alias_protected?(_record_id) = false

        sig { params(_record: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
        def range_basis_changed?(_record) = false

        sig { params(_record_id: String).returns(T::Boolean) }
        def history_required?(_record_id) = true

        sig { params(_record_id: String, _boundary: String).returns(T::Boolean) }
        def fixed_boundary_valid?(_record_id, _boundary) = true

        sig { void }
        def record_history_walk; end

        sig { params(_formula_name: String).void }
        def record_history_unavailable(_formula_name); end

        sig { params(_record_id: String).returns(T.nilable(Symbol)) }
        def reviewed_range_state(_record_id); end

        sig { params(_record_id: String, _boundary: String).returns(T::Boolean) }
        def reintroduction_boundary_valid?(_record_id, _boundary) = true

        sig {
          params(record: T::Hash[Symbol, T.untyped], revalidated: T::Boolean, initial_introduction: T::Boolean).void
        }
        def emit(record, revalidated: false, initial_introduction: false); end

        sig { void }
        def finish; end
      end

      class DirEmitter < Emitter
        sig {
          params(dir: String, verbose: T::Boolean, close_open_ranges: T::Boolean, reconcile_history: T::Boolean,
                 formula_names: T.nilable(T::Array[String])).void
        }
        def initialize(dir, verbose:, close_open_ranges:, reconcile_history: false, formula_names: nil)
          super()
          FileUtils.mkdir_p(dir)
          @dir = dir
          @verbose = verbose
          @close_open_ranges = close_open_ranges
          @reconcile_history = reconcile_history
          @formula_names = formula_names
          @deleted = T.let(0, Integer)
          @reconciliation_skips = T.let({}, T::Hash[Symbol, Integer])
          @reconciliation_seen = T.let({}, T::Hash[String, T::Boolean])
          @written = T.let(0, Integer)
          @unchanged = T.let(0, Integer)
          @skipped_generated = T.let(0, Integer)
          @basis_changed = T.let(0, Integer)
          @history_walks = T.let(0, Integer)
          @history_unavailable_by_formula = T.let({}, T::Hash[String, Integer])
          @alias_targets = T.let({}, T::Hash[String, T::Array[String]])
          @protected_aliases = T.let({}, T::Hash[String, T::Boolean])
          @alias_records = T.let({}, T::Hash[String, T.untyped])
          @identity_paths = T.let({}, T::Hash[String, T::Array[String]])
          @path_identities = T.let({}, T::Hash[String, T::Array[String]])
          @alias_index_loaded = T.let(false, T::Boolean)
        end

        sig {
          override.params(formula_name: String, groups: T::Hash[String, T::Array[String]])
                  .returns(T::Array[String])
        }
        def prepare_aliases(formula_name, groups)
          ensure_alias_index
          errors = T.let([], T::Array[String])
          targets = T.let({}, T::Hash[String, T::Array[String]])
          protected = T.let({}, T::Hash[String, T::Boolean])
          owners = T.let({}, T::Hash[String, String])
          identity_owners = T.let({}, T::Hash[String, String])
          generated_paths = T.let([], T::Array[String])

          groups.each do |canonical_id, record_ids|
            record_ids.each do |record_id|
              if (owner = identity_owners[record_id]) && owner != canonical_id
                errors << "#{canonical_id}: identity also belongs to #{owner}; leaving both unchanged"
              else
                identity_owners[record_id] = canonical_id
              end
            end
            paths = matching_alias_paths(record_ids)
            paths.each do |path|
              if (owner = owners[path]) && owner != canonical_id
                errors << "#{canonical_id}: alias family also belongs to #{owner}; leaving both unchanged"
              else
                owners[path] = canonical_id
              end
            end

            writable = T.let([], T::Array[String])
            generated = T.let([], T::Array[String])
            paths.each do |path|
              existing = alias_record(path)
              if existing == :malformed
                errors << "#{canonical_id}: malformed alias #{path}; leaving family unchanged"
                next
              end
              unless existing.is_a?(Hash)
                errors << "#{canonical_id}: invalid alias #{path}; leaving family unchanged"
                next
              end
              if existing["id"] != File.basename(path, ".json")
                errors << "#{canonical_id}: #{path} has a mismatched id; leaving family unchanged"
                next
              end

              affected = existing["affected"]
              names = affected_formula_names(existing)
              if !affected.is_a?(Array) || !affected.one? || names != [formula_name]
                errors << "#{canonical_id}: #{path} has unsupported affected entries for " \
                          "#{formula_name}; leaving family unchanged"
                next
              end

              database_specific = existing["database_specific"]
              source = database_specific["source"] if database_specific.is_a?(Hash)
              if source == "generated"
                generated << path
                next
              end
              if source != "matched"
                errors << "#{canonical_id}: #{path} has unsupported source " \
                          "#{source.inspect}; leaving family unchanged"
                next
              end

              writable << path
            end

            if generated.any?
              targets[canonical_id] = []
              protected[canonical_id] = true
              generated_paths.concat(generated)
              next
            end
            if writable.length > 1
              errors << "#{canonical_id}: multiple alias records found; consolidate the family before matching"
              next
            end

            canonical_path = record_path(canonical_id)
            targets[canonical_id] = if writable.one?
              writable
            else
              [canonical_path]
            end
            protected[canonical_id] = false
          end
          return errors.uniq if errors.any?

          @alias_targets.merge!(targets)
          @protected_aliases.merge!(protected)
          @skipped_generated += generated_paths.uniq.length
          []
        end

        sig { override.params(record_id: String).returns(T::Boolean) }
        def alias_protected?(record_id)
          @protected_aliases.fetch(record_id, false)
        end

        # Only pure registry-resource records can supply fallback query hints.
        # Mixed or incomplete provenance retains the ordinary discovery guard.
        sig { params(formula_name: String).returns(T::Array[Homebrew::Vulns::Match::ResourceRecord]) }
        def reconciliation_resource_records(formula_name)
          fields = %w[ecosystem name resource subject_version key]
          Dir.glob(File.join(@dir, "BREW-#{formula_name}-*.json")).filter_map do |path|
            record = alias_record(path)
            next unless record.is_a?(Hash)
            next unless reconcilable_record?(record)
            next unless single_terminal_range?(record)
            next if affected_formula_names(record) != [formula_name]
            next if record["id"] != File.basename(path, ".json")

            upstream = record["upstream"]
            next unless upstream.is_a?(Array)
            next if upstream.empty? || !upstream.all?(String)

            rows = record.dig("database_specific", "upstream_evidence")
            next unless rows.is_a?(Array)
            next if rows.empty?

            evidence = rows.filter_map do |row|
              next unless row.is_a?(Hash)
              next if row["strategy"] != "registry"
              next unless fields.all? do |field|
                row[field].is_a?(String) && row[field].present?
              end

              Homebrew::Vulns::Match::Evidence.new(
                strategy: :registry, ecosystem: row.fetch("ecosystem"), name: row.fetch("name"),
                resource: row.fetch("resource"), subject_version: row.fetch("subject_version"), key: row.fetch("key")
              ).freeze
            end
            next if evidence.length != rows.length

            Homebrew::Vulns::Match::ResourceRecord.new(id: record.fetch("id"), upstream:, evidence: evidence.uniq)
          end
        end

        # Reconciliation never creates a record or changes its matching provenance.
        sig { params(record: T::Hash[Symbol, T.untyped]).returns(T.nilable(T::Hash[String, T.untyped])) }
        def reconciliation_record(record)
          id = record.fetch(:id)
          if alias_protected?(id)
            skip_reconciliation(id, [:alias_protected])
            return
          end

          paths = alias_target_paths(id)
          unless paths.one?
            skip_reconciliation(id, [:ambiguous_alias_paths])
            return
          end
          return unless File.file?(paths.fetch(0))

          path = paths.fetch(0)
          @reconciliation_seen[path] = true
          existing = alias_record(path)
          unless reconcilable_record?(existing)
            skip_reconciliation(id, [:unsupported_record])
            return
          end
          unless single_terminal_range?(existing)
            skip_reconciliation(id, [:unsupported_range])
            return
          end
          unless provenance_matches?(existing, record)
            skip_reconciliation(id, [:provenance_changed])
            return
          end
          existing
        end

        # Only matched, bump-fixed records are reconciled; generated patch
        # fixes and withdrawn records keep their annotation-based ranges.
        sig { params(existing: T.untyped).returns(T::Boolean) }
        def reconcilable_record?(existing)
          existing.is_a?(Hash) &&
            existing.dig("database_specific", "source") == "matched" &&
            existing["withdrawn"].blank? &&
            existing.dig("affected", 0, "ecosystem_specific", "fix") == "bump"
        end

        # Exactly one ECOSYSTEM range holding an `introduced` and a `fixed`
        # event, each a non-blank string.
        sig { params(existing: T::Hash[String, T.untyped]).returns(T::Boolean) }
        def single_terminal_range?(existing)
          ranges = existing.dig("affected", 0, "ranges")
          return false if !ranges.is_a?(Array) || !ranges.one?

          range = ranges.fetch(0)
          return false if !range.is_a?(Hash) || range["type"] != "ECOSYSTEM"

          events = range["events"]
          return false if !events.is_a?(Array) || events.length != 2

          introduced, fixed = events
          introduced.is_a?(Hash) && introduced.keys == ["introduced"] && introduced["introduced"].is_a?(String) &&
            introduced["introduced"].present? &&
            fixed.is_a?(Hash) && fixed.keys == ["fixed"] && fixed["fixed"].is_a?(String) && fixed["fixed"].present?
        end

        # The stored record must still be reached through the same upstream
        # identifiers with evidence and a range basis the candidate reproduces.
        sig { params(existing: T::Hash[String, T.untyped], record: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
        def provenance_matches?(existing, record)
          upstream = existing["upstream"]
          return false if !upstream.is_a?(Array) || upstream.empty?
          return false if (upstream - record.fetch(:upstream)).any?
          return false if Array(existing.dig("database_specific", "upstream_evidence")).empty?

          range_basis(existing) == range_basis(record)
        end

        sig { params(record_id: String, reasons: T::Array[Symbol]).void }
        def skip_reconciliation(record_id, reasons)
          reasons.each { |reason| @reconciliation_skips[reason] = @reconciliation_skips.fetch(reason, 0) + 1 }
          Utils::Output.opoo "#{record_id}: #{reasons.join(", ")}; leaving it unchanged" if @verbose
        end

        sig { params(record: T::Hash[Symbol, T.untyped], result: Homebrew::Vulns::Match::ReconciledHistory).void }
        def reconcile(record, result)
          existing = reconciliation_record(record)
          return unless existing

          id = record.fetch(:id)
          path = alias_target_paths(id).fetch(0)
          updated = existing.deep_dup
          if result.state == :range && (introduced = result.introduced) && (fixed = result.fixed)
            events = existing.fetch("affected").fetch(0).fetch("ranges").fetch(0).fetch("events")
            old_introduced = PkgVersion.parse(events.fetch(0).fetch("introduced"))
            old_fixed = PkgVersion.parse(events.fetch(1).fetch("fixed"))
            if PkgVersion.parse(introduced) >= PkgVersion.parse(fixed)
              skip_reconciliation(id, [:invalid_interval])
              return
            end
            if PkgVersion.parse(introduced) < old_introduced || PkgVersion.parse(fixed) > old_fixed
              skip_reconciliation(id, [:range_expansion])
              return
            end
            updated.fetch("affected").fetch(0).fetch("ranges").fetch(0)["events"] = [
              { "introduced" => introduced }, { "fixed" => fixed }
            ]
            if updated == existing
              @unchanged += 1
              return
            end
            updated["modified"] = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
          elsif result.state == :range && result.fixed.nil?
            skip_reconciliation(id, [:reopened])
            return
          elsif result.state != :never_affected
            skip_reconciliation(id, result.reasons.presence || [:unsupported_result])
            return
          end

          # A full walk can be slow. Do not overwrite an intervening review edit.
          if !File.file?(path) || JSON.parse(File.read(path)) != existing
            skip_reconciliation(id, [:record_changed])
            return
          end
          if result.state == :never_affected
            File.unlink(path)
            @deleted += 1
            puts "  deleted #{path}" if @verbose
          else
            File.write(path, "#{JSON.pretty_generate(updated)}\n")
            @written += 1
            puts "  reconciled #{path}" if @verbose
          end
        rescue JSON::ParserError
          skip_reconciliation(record.fetch(:id), [:record_changed])
        end

        sig { override.params(record: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
        def range_basis_changed?(record)
          alias_target_paths(record.fetch(:id)).any? do |path|
            next false unless File.file?(path)

            existing = alias_record(path)
            existing.is_a?(Hash) && range_basis(existing) != range_basis(record)
          end
        end

        sig {
          override.params(record: T::Hash[Symbol, T.untyped], revalidated: T::Boolean, initial_introduction: T::Boolean).void
        }
        def emit(record, revalidated: false, initial_introduction: false)
          updates = alias_target_paths(record.fetch(:id)).filter_map do |path|
            candidate = record.deep_dup
            existing = alias_record(path) if File.file?(path)
            if existing.is_a?(Hash)
              candidate[:id] = existing.fetch("id")
              candidate[:upstream] = (Array(existing["upstream"]) + Array(candidate[:upstream])).uniq
              existing_basis = range_basis(existing)
              candidate_basis = range_basis(candidate)
              if existing_basis != candidate_basis
                ranges = JSON.parse(JSON.generate(candidate)).dig("affected", 0, "ranges")
                existing_ranges = existing.dig("affected", 0, "ranges")
                no_reviewed_ranges = Array(existing_ranges).none? do |range|
                  Homebrew::Vulns::OsvExport.ranges_open?([range]) ||
                    Homebrew::Vulns::OsvExport.ranges_terminal?([range])
                end
                compatible = ranges == existing_ranges || (@close_open_ranges && no_reviewed_ranges)
                if !compatible || (!revalidated && !Homebrew::Vulns::OsvExport.ranges_open?(ranges))
                  fields = (existing_basis.keys | candidate_basis.keys).reject do |key|
                    existing_basis[key] == candidate_basis[key]
                  end
                  Utils::Output.onoe "#{candidate[:id]}: reviewed range basis changed (#{fields.join(", ")}); " \
                                     "leaving it unchanged.\n" \
                                     "Run advisory-match for this formula with --json and history enabled,\n" \
                                     "then review and update its ranges and provenance together."
                  @basis_changed += 1
                  Homebrew.failed = true
                  next
                end
              end
            elsif File.file?(path)
              candidate[:id] = File.basename(path, ".json")
            end
            merged = Homebrew::Vulns::OsvExport.merge_existing(
              path, candidate, close_open_ranges: @close_open_ranges, initial_introduction:
            )
            [path, merged]
          end

          updates.each do |path, merged|
            if merged.nil?
              @unchanged += 1
              next
            end
            File.write(path, "#{JSON.pretty_generate(merged)}\n")
            puts "  wrote #{path}" if @verbose
            @written += 1
          end
        end

        # Keep every strategy and runtime subject. Ignore version values and
        # resource labels, but retain checkability and separate copies of the
        # same resource package: either can change the aggregate history.
        sig { params(record: T::Hash[T.untyped, T.untyped]).returns(T::Hash[String, T.untyped]) }
        def range_basis(record)
          record = JSON.parse(JSON.generate(record))
          affected = record["affected"]
          return {} unless affected.is_a?(Array)
          return {} unless affected.one?

          entry = affected.fetch(0)
          return {} unless entry.is_a?(Hash)

          ecosystem_specific = entry["ecosystem_specific"]
          ecosystem_specific = {} unless ecosystem_specific.is_a?(Hash)

          database_specific = record["database_specific"]
          evidence = Array(database_specific["upstream_evidence"]) if database_specific.is_a?(Hash)
          evidence = Array(evidence).grep(Hash)
          subjects = evidence.group_by { |row| row["resource"] }.map do |resource, rows|
            identities = rows.filter_map do |row|
              identity = subject_identity(row)
              next if identity.empty?

              [row["strategy"].to_s, identity, row["subject_version"].nil? ? "unknown" : "versioned"]
            end
            [resource ? "resource" : "primary", identities.uniq.sort]
          end
          basis = { "subjects" => subjects.sort }
          resource_purl = ecosystem_specific["resource_purl"]
          if resource_purl.is_a?(String)
            resource = evidence.find { |row| row["resource"] && row["key"] == resource_purl }
            basis["resource_purl"] = resource ? subject_identity(resource) : [unversioned_key(resource_purl)]
          end
          upstream_fixed_in = ecosystem_specific["upstream_fixed_in"]
          basis["upstream_fixed_in"] = upstream_fixed_in if upstream_fixed_in.is_a?(String)
          basis
        end

        sig { params(evidence: T::Hash[String, T.untyped]).returns(T::Array[String]) }
        def subject_identity(evidence)
          ecosystem = evidence["ecosystem"]
          name = evidence["name"]
          return [ecosystem, name] if ecosystem.is_a?(String) && name.is_a?(String)

          key = evidence["key"]
          key.is_a?(String) ? [unversioned_key(key)] : []
        end

        sig { params(key: String).returns(String) }
        def unversioned_key(key)
          key = key.delete_prefix("upstream:")
          key.start_with?("pkg:") ? key.sub(%r{@[^/@]*\z}, "") : key
        end

        sig { override.params(record_id: String).returns(T::Boolean) }
        def history_required?(record_id)
          alias_target_paths(record_id).any? do |path|
            next true unless File.file?(path)

            existing = alias_record(path)
            next true unless existing.is_a?(Hash)

            affected = existing["affected"]
            next true unless affected.is_a?(Array)
            next true if affected.empty?

            affected.any? do |entry|
              !entry.is_a?(Hash) ||
                !Homebrew::Vulns::OsvExport.ranges_terminal?(homebrew_ranges(entry["ranges"]))
            end
          end
        end

        sig { override.params(record_id: String, boundary: String).returns(T::Boolean) }
        def fixed_boundary_valid?(record_id, boundary)
          alias_target_paths(record_id).all? do |path|
            next true unless File.file?(path)

            existing = alias_record(path)
            next false unless existing.is_a?(Hash)

            affected = existing["affected"]
            next false unless affected.is_a?(Array)

            affected.all? do |entry|
              entry.is_a?(Hash) &&
                Homebrew::Vulns::OsvExport.fixed_follows?(homebrew_ranges(entry["ranges"]), boundary)
            end
          end
        end

        sig { override.params(record_id: String).returns(T.nilable(Symbol)) }
        def reviewed_range_state(record_id)
          paths = alias_target_paths(record_id).select { |path| File.file?(path) }
          states_by_path = paths.map { |path| reviewed_states(path) }
          return if states_by_path.any?(&:nil?)

          states = states_by_path.flatten
          return if states.empty?

          states.fetch(0)
        end

        sig { override.params(record_id: String, boundary: String).returns(T::Boolean) }
        def reintroduction_boundary_valid?(record_id, boundary)
          alias_target_paths(record_id).all? do |path|
            next true unless File.file?(path)

            existing = alias_record(path)
            next false unless existing.is_a?(Hash)

            affected = existing["affected"]
            next false unless affected.is_a?(Array)

            affected.all? do |entry|
              next false unless entry.is_a?(Hash)

              ranges = homebrew_ranges(entry["ranges"])
              Homebrew::Vulns::OsvExport.reintroduction_follows?(ranges, boundary)
            end
          end
        end

        sig { override.void }
        def record_history_walk
          @history_walks += 1
          puts "  #{@history_walks} history walks" if @verbose && (@history_walks % 100).zero?
        end

        sig { override.params(formula_name: String).void }
        def record_history_unavailable(formula_name)
          count = @history_unavailable_by_formula.fetch(formula_name, 0)
          @history_unavailable_by_formula[formula_name] = count + 1
        end

        sig { params(formula_name: String).void }
        def record_upstream_unavailable(formula_name)
          ensure_alias_index
          @alias_records.each do |path, record|
            next unless record.is_a?(Hash)
            next if record.dig("database_specific", "source") != "matched"
            next unless affected_formula_names(record).include?(formula_name)

            @reconciliation_seen[path] = true
            skip_reconciliation(record.fetch("id"), [:upstream_unavailable])
          end
        end

        sig { params(record_id: String).returns(String) }
        def record_path(record_id)
          File.join(@dir, "#{record_id}.json")
        end

        sig { params(record_id: String).returns(T::Array[String]) }
        def alias_target_paths(record_id)
          @alias_targets.fetch(record_id) { [record_path(record_id)] }
        end

        sig { params(path: String).returns(T.untyped) }
        def alias_record(path)
          return @alias_records[path] if @alias_records.key?(path)

          @alias_records[path] = JSON.parse(File.read(path))
        rescue JSON::ParserError
          @alias_records[path] = :malformed
        end

        sig { params(record: T::Hash[String, T.untyped]).returns(T::Array[String]) }
        def affected_formula_names(record)
          Array(record["affected"]).filter_map do |entry|
            next unless entry.is_a?(Hash)

            package = entry["package"]
            next unless package.is_a?(Hash)
            next if package["ecosystem"] != Homebrew::Vulns::OsvExport::ECOSYSTEM

            package["name"]
          end.uniq
        end

        sig { void }
        def ensure_alias_index
          return if @alias_index_loaded

          Dir.glob(File.join(@dir, "BREW-*.json")).each do |path|
            existing = alias_record(path)
            next unless existing.is_a?(Hash)

            formula_names = affected_formula_names(existing)
            next unless formula_names.one?

            identities = Array(existing["upstream"]).grep(String).map do |id|
              "BREW-#{formula_names.fetch(0)}-#{id}"
            end.uniq
            @path_identities[path] = identities
            identities.each { |identity| (@identity_paths[identity] ||= []) << path }
          end
          @alias_index_loaded = true
        end

        sig { params(record_ids: T::Array[String]).returns(T::Array[String]) }
        def matching_alias_paths(record_ids)
          pending = record_ids.dup
          identities = T.let({}, T::Hash[String, T::Boolean])
          paths = T.let({}, T::Hash[String, T::Boolean])
          until pending.empty?
            identity = pending.shift
            next if identity.nil? || identities[identity]

            identities[identity] = true
            direct = record_path(identity)
            linked = [direct, *@identity_paths.fetch(identity, [])]
            linked.each do |path|
              next unless File.file?(path)
              next if paths[path]

              paths[path] = true
              pending.concat(@path_identities.fetch(path, []))
            end
          end
          paths.keys.sort
        end

        sig { params(path: String).returns(T.nilable(T::Array[Symbol])) }
        def reviewed_states(path)
          existing = alias_record(path)
          return unless existing.is_a?(Hash)

          affected = existing["affected"]
          return unless affected.is_a?(Array)
          return if affected.empty?

          states = affected.filter_map do |entry|
            next unless entry.is_a?(Hash)

            ranges = homebrew_ranges(entry["ranges"])
            if Homebrew::Vulns::OsvExport.ranges_terminal?(ranges)
              :terminal
            elsif Homebrew::Vulns::OsvExport.ranges_open?(ranges)
              :open
            end
          end
          return if states.length != affected.length

          states
        end

        sig { params(ranges: T.untyped).returns(T::Array[T.untyped]) }
        def homebrew_ranges(ranges)
          Array(ranges).select do |range|
            range.is_a?(Hash) && range["type"] == "ECOSYSTEM"
          end
        end

        sig { override.void }
        def finish
          history_unavailable = @history_unavailable_by_formula.values.sum
          Utils::Output.ohai "#{@written} records written to #{@dir} " \
                             "(#{@unchanged} unchanged, #{@skipped_generated} generated left as-is, " \
                             "#{@history_walks} history walks, #{history_unavailable} history-unavailable skips, " \
                             "#{@basis_changed} range-basis skips)"
          if @reconcile_history
            ensure_alias_index
            formula_names = @formula_names
            unmatched = @alias_records.count do |path, record|
              next false unless record.is_a?(Hash)
              next false if formula_names&.exclude?(record.dig("affected", 0, "package", "name"))

              record.dig("database_specific", "source") == "matched" && !@reconciliation_seen[path]
            end
            puts "  Reconciliation: #{@deleted} deleted; #{unmatched} matched records not revisited"
            @reconciliation_skips.sort.each { |reason, count| puts "    #{reason}: #{count}" }
          end
          return if @history_unavailable_by_formula.empty?

          puts "  Unavailable history by formula:"
          @history_unavailable_by_formula.sort.each { |formula, count| puts "    #{formula}: #{count}" }
        end
      end

      class JsonEmitter < Emitter
        sig { void }
        def initialize
          super
          @records = T.let([], T::Array[T::Hash[Symbol, T.untyped]])
        end

        sig {
          override.params(record: T::Hash[Symbol, T.untyped], revalidated: T::Boolean, initial_introduction: T::Boolean).void
        }
        def emit(record, revalidated: false, initial_introduction: false)
          @records << record
        end

        sig { override.void }
        def finish
          puts JSON.pretty_generate(@records)
        end
      end

      class CountEmitter < Emitter
        sig { void }
        def initialize
          super
          @count = T.let(0, Integer)
        end

        sig {
          override.params(_record: T::Hash[Symbol, T.untyped], revalidated: T::Boolean, initial_introduction: T::Boolean).void
        }
        def emit(_record, revalidated: false, initial_introduction: false)
          @count += 1
        end

        sig { override.void }
        def finish
          Utils::Output.ohai "#{@count} candidate records"
        end
      end

      sig { params(formula_names: T.nilable(T::Array[String])).returns(Emitter) }
      def build_emitter(formula_names: nil)
        if (dir = args.output)
          DirEmitter.new(dir, verbose: args.verbose?, close_open_ranges: !args.no_history?,
                         reconcile_history: args.reconcile_history?, formula_names:)
        elsif args.json?
          JsonEmitter.new
        else
          CountEmitter.new
        end
      end

      sig { params(matcher: Homebrew::Vulns::Match).void }
      def emit_index(matcher)
        tap = CoreTap.instance
        raise TapUnavailableError, tap.name unless tap.installed?

        index = tap.formula_names.each_with_object({}) do |name, h|
          identity = matcher.identify(Formulary.factory(name))
          next unless identity.identifiable?

          h[name] = {
            git_repo:          identity.git_repo,
            git_tag:           identity.git_tag,
            primary_package:   identity.primary_package&.to_h,
            resource_packages: identity.resource_packages.transform_values(&:to_h),
            distro_packages:   identity.distro_packages,
          }.compact
        rescue => e
          onoe "Error loading formula '#{name}': #{e}"
        end
        puts JSON.pretty_generate(index)
      end
    end
  end
end
