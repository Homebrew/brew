# typed: strict
# frozen_string_literal: true

require "api/env"
require "abstract_command"
require "formula"
require "vulns/history"
require "vulns/osv_export"

module Homebrew
  module DevCmd
    class GenerateVulnsAdvisories < AbstractCommand
      cmd_args do
        description <<~EOS
          Generate OSV-schema advisory records for the `Homebrew` ecosystem from
          `homebrew/core` formula patch `resolves` annotations, for
          <https://github.com/Homebrew/advisory-database>.

          Records are written to <directory>.
        EOS
        switch "-n", "--dry-run",
               description: "List the records that would be generated without writing files or querying OSV.dev."

        named_args :directory, number: 1

        hide_from_man_page!
      end

      sig { override.void }
      def run
        tap = CoreTap.instance
        raise TapUnavailableError, tap.name unless tap.installed?

        dir = args.named.fetch(0)

        Formulary.enable_factory_cache!
        Homebrew::API.with_no_api_env do
          latest_macos = MacOSVersion.new((HOMEBREW_MACOS_NEWEST_UNSUPPORTED.to_i - 1).to_s).to_sym
          Homebrew::SimulateSystem.with(os: latest_macos, arch: :arm) do
            annotated = tap.formula_names.filter_map do |name|
              formula = Formulary.factory(name)
              patches = all_variation_patches(formula)
              [formula, patches] if Homebrew::Vulns::Scanner.resolved_ids(patches).any?
            rescue
              onoe "Error loading formula '#{name}'."
              raise
            end
            ohai "#{annotated.size} formulae with security `resolves` annotations"

            if args.dry_run?
              annotated.each do |formula, patches|
                Homebrew::Vulns::Scanner.resolved_ids(patches).each do |vuln_id|
                  puts "#{Homebrew::Vulns::OsvExport::ID_PREFIX}-#{formula.name}-#{vuln_id}"
                end
              end
              next
            end

            written = Homebrew::Vulns::OsvExport.run(
              annotated, dir,
              first_fixed: ->(formula, vuln_id) { first_fixed_version(formula, vuln_id) }
            )
            written.each { |p| puts "  wrote #{p}" } if args.verbose?
            ohai "#{written.size} records written to #{dir}"
          end
        end
      end

      # `Formula#serialized_patches` reflects the currently simulated OS and
      # architecture; a `patch` inside e.g. `on_linux` is invisible under
      # `SimulateSystem.with(os: :sequoia)`. Collect the union of the base
      # `patches` array and every OS/arch variation from
      # `Formula#to_hash_with_variations` so platform-gated `resolves`
      # annotations are exported.
      sig { params(formula: Formula).returns(T::Array[T::Hash[String, T.untyped]]) }
      def all_variation_patches(formula)
        hash = formula.to_hash_with_variations
        base = hash.fetch("patches")
        variation_patches = hash.fetch("variations").values.filter_map { |v| v["patches"] }
        (base + variation_patches.flatten(1)).uniq
      end

      # Walk homebrew-core git history (newest first) via
      # {Homebrew::Vulns::History} and return the `pkg_version` at the oldest
      # revision where `vuln_id` still appears in the formula's resolved patch
      # ids: the version at which the fix first shipped. Untrusted history (a
      # shallow clone, no git history or a revision that fails to load) returns
      # `:history_unavailable` so the caller skips the record rather than
      # inventing a boundary. Only invoked for records with no existing file,
      # so the cost is bounded to newly annotated (formula, CVE) pairs.
      #
      # Because `resolved_ids` includes CVEs inferred from patch URLs and
      # `apply` file paths, this finds the true fix version when the CVE is
      # named there. When a `resolves` line was added to a patch that had
      # already shipped without a CVE reference, it finds when `resolves` was
      # added (too recent); those cases are hand-corrected in the advisory
      # repository, which {Homebrew::Vulns::OsvExport.run} then preserves.
      #
      # Historical revisions are loaded under the enclosing {SimulateSystem}
      # (latest macOS/ARM) only; a `resolves` that lives inside e.g. `on_linux`
      # is invisible here and falls through to the current `pkg_version`.
      # {FormulaVersions} caches by revision alone, so per-variation historical
      # loading would need separate instances; deferred until a variation-only
      # security annotation actually exists in core.
      sig { params(formula: Formula, vuln_id: String).returns(T.any(String, Symbol)) }
      def first_fixed_version(formula, vuln_id)
        # The path-filtered `git rev-list` over the whole homebrew-core history
        # dominates runtime; {Homebrew::Vulns::History} caches it per formula
        # so subsequent CVEs for the same formula reuse it.
        @history ||= T.let(Homebrew::Vulns::History.new, T.nilable(Homebrew::Vulns::History))

        last_fixed = T.let(formula.pkg_version.to_s, String)
        result = @history.walk(formula) do |old|
          next last_fixed unless Homebrew::Vulns::Scanner.resolved_ids(old.serialized_patches).include?(vuln_id)

          last_fixed = old.pkg_version.to_s
          nil
        end
        if result == :history_unavailable
          record_id = Homebrew::Vulns::OsvExport.record_id(formula, vuln_id)
          opoo "#{record_id}: formula history is unavailable; skipping automatic generation"
          return :history_unavailable
        end

        # An exhausted walk means every revision resolved the CVE.
        result || last_fixed
      end
    end
  end
end
