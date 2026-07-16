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

          With no arguments, installed formulae are checked unless tap trust is configured,
          in which case all formulae permitted by the trust configuration are checked.
        EOS
        switch "-d", "--deps",
               description: "Also check the dependencies of named formulae."
        switch "--no-ignore-patches",
               description: "Report vulnerabilities even when a formula patch resolves them."
        flag   "--brewfile",
               description: "Check formulae listed in a Brewfile. " \
                            "Defaults to `./Brewfile`; use `--brewfile=`<path> to specify another."
        flag   "-s", "--severity=",
               description: "Only report findings at or above: `low`, `medium`, `high`, `critical`."
        flag   "-m", "--max-summary=",
               description: "Truncate summaries to <n> characters (default 60, 0 for no limit)."
        switch "-j", "--json",
               description: "Output JSON."

        named_args :formula
      end

      sig { override.void }
      def run
        require "vulns"

        summary_width = max_summary

        results = Homebrew::Vulns::Scanner.new(
          formulae,
          ignore_patches: !args.no_ignore_patches?,
          min_severity:,
        ).scan

        if args.json?
          Homebrew::Vulns::Output.json(results)
        else
          Homebrew::Vulns::Output.text(results, max_summary: summary_width)
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
        list = if (brewfile = args.brewfile)
          require "bundle/brewfile"
          Homebrew::Bundle::Brewfile.read(file: brewfile_path(brewfile)).entries
                                    .select { |e| e.type == :brew }
                                    .map { |e| Formulary.resolve(e.name) }
        elsif args.named.any?
          args.named.to_resolved_formulae
        elsif Homebrew::EnvConfig.tap_trust_configured?
          Formula.all
        else
          Formula.installed
        end
        list += list.flat_map { |f| f.recursive_dependencies.map(&:to_formula) } if args.deps?
        list.uniq(&:full_name)
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
