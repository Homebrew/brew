# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "formula"

module Homebrew
  module Cmd
    class Vulns < AbstractCommand
      SEVERITIES = %w[low medium high critical].freeze

      cmd_args do
        description <<~EOS
          Check <formula> for known security vulnerabilities using the OSV.dev database.

          With no arguments, all installed formulae are checked.
        EOS
        switch "-d", "--deps",
               description: "Also check the dependencies of named formulae."
        switch "--no-ignore-patches",
               description: "Report vulnerabilities even when a formula patch resolves them."
        flag   "--brewfile",
               description: "Check formulae listed in a Brewfile. " \
                            "Defaults to `./Brewfile`; use `--brewfile=`<path> to specify another."
        switch "--fix-available",
               description: "Only report vulnerabilities that have a fix available. " \
                            "Note that this may exclude vulnerabilities with fixes available " \
                            "if we cannot determine that the fix is included in the version " \
                            "under consideration."
        switch "--no-fix-available",
               description: "Only report vulnerabilities that do not have a fix available. " \
                            "Note that this may include vulnerabilities with fixes available " \
                            "if we cannot determine that the fix is included in the version " \
                            "under consideration."
        flag   "-s", "--severity=",
               description: "Only report findings at or above: `low`, `medium`, `high`, `critical`."
        flag   "-m", "--max-summary=",
               description: "Truncate summaries to <n> characters (default 60, 0 for no limit)."
        switch "-j", "--json",
               description: "Output JSON."

        conflicts "--fix-available", "--no-fix-available"

        named_args :formula
      end

      sig { override.void }
      def run
        require "vulns"

        summary_width = max_summary
        severity = min_severity

        results = Homebrew::Vulns::Scanner.new(
          formulae,
          ignore_patches: !args.no_ignore_patches?,
          min_severity:   severity,
          only_fixed:     args.fix_available?,
          except_fixed:   args.no_fix_available?,
        ).scan

        if args.json?
          Homebrew::Vulns::Output.json(results)
        else
          Homebrew::Vulns::Output.text(results, max_summary: summary_width)
        end

        if untrusted_skipped.any?
          kegs = Utils.pluralize("installed keg", untrusted_skipped.size, include_count: true)
          opoo <<~EOS
            #{kegs} from an untrusted tap not scanned:
              #{untrusted_skipped.join("\n  ")}
            Run `brew trust` on the formula or tap to include it in future scans.
          EOS
          Homebrew.failed = true
        end
        if results.outdated_without_sbom.any?
          opoo <<~EOS
            The installed source of #{results.outdated_without_sbom.sort.join(", ")} could not be determined
            (older than the current formula and no SBOM was written at install time). Results above reflect
            the current formula version, not what is installed. Run `brew upgrade` for accurate results.
          EOS
          Homebrew.failed = true
        end
        Homebrew.failed = true if results.any_open?
      end

      sig { returns(T::Array[Formula]) }
      def formulae
        list = T.let([], T::Array[Formula])
        if (brewfile = args.brewfile)
          require "bundle/brewfile"
          list += Homebrew::Bundle::Brewfile.read(file: brewfile_path(brewfile)).entries
                                            .select { |e| e.type == :brew }
                                            .map { |e| Formulary.resolve(e.name) }
        end
        list += args.named.to_resolved_formulae if args.named.any?
        list = installed_formulae if !args.brewfile && args.no_named?
        list += list.flat_map { |f| f.recursive_dependencies.map(&:to_formula) } if args.deps?
        list.uniq(&:full_name)
      end

      sig { returns(T::Array[Formula]) }
      def installed_formulae
        Formula.racks.filter_map do |rack|
          Formulary.from_rack(rack)
        rescue Homebrew::UntrustedTapError => e
          untrusted_skipped << e.message.lines.first.to_s.strip
          nil
        rescue
          nil
        end.uniq(&:name)
      end

      sig { returns(T::Array[String]) }
      def untrusted_skipped
        @untrusted_skipped ||= T.let([], T.nilable(T::Array[String]))
      end

      # A bare `--brewfile` (no `=path`) yields `true` from OptionParser at
      # runtime; the generated RBI types it as `T.nilable(String)`, so accept
      # the wider type here and normalise `true`/`""` to the `nil` default.
      sig { params(value: T.nilable(T.any(String, TrueClass))).returns(T.nilable(String)) }
      def brewfile_path(value)
        value.presence if value.is_a?(String)
      end

      sig { returns(T.nilable(Symbol)) }
      def min_severity
        raw = args.severity
        return if raw.nil?

        raw = raw.downcase
        raise UsageError, "`--severity` must be one of: #{SEVERITIES.join(", ")}" unless SEVERITIES.include?(raw)

        raw.to_sym
      end

      sig { returns(Integer) }
      def max_summary
        raw = args.max_summary
        return Homebrew::Vulns::Output::DEFAULT_MAX_SUMMARY if raw.nil?

        raise UsageError, "`--max-summary` must be a non-negative integer" unless raw.match?(/\A\d+\z/)

        raw.to_i
      end
    end
  end
end
