# typed: strict
# frozen_string_literal: true

module Homebrew
  module Vulns
    # CVSS v3.0/v3.1 base score and qualitative severity rating.
    # See https://www.first.org/cvss/v3-1/specification-document.
    # v2 and v4.0 vectors return `nil` so callers fall through to the next
    # available severity source.
    module CVSS
      AV = T.let({ "N" => 0.85, "A" => 0.62, "L" => 0.55, "P" => 0.2 }.freeze, T::Hash[String, Float])
      AC = T.let({ "L" => 0.77, "H" => 0.44 }.freeze, T::Hash[String, Float])
      UI = T.let({ "N" => 0.85, "R" => 0.62 }.freeze, T::Hash[String, Float])
      CIA = T.let({ "N" => 0.0, "L" => 0.22, "H" => 0.56 }.freeze, T::Hash[String, Float])
      PR_UNCHANGED = T.let({ "N" => 0.85, "L" => 0.62, "H" => 0.27 }.freeze, T::Hash[String, Float])
      PR_CHANGED = T.let({ "N" => 0.85, "L" => 0.68, "H" => 0.50 }.freeze, T::Hash[String, Float])
      private_constant :AV, :AC, :UI, :CIA, :PR_UNCHANGED, :PR_CHANGED

      BASE_METRICS = %w[AV AC PR UI S C I A].freeze
      private_constant :BASE_METRICS

      sig { params(vector: String).returns(T.nilable(Float)) }
      def self.base_score(vector)
        metrics = parse(vector)
        return if metrics.nil?

        scope_changed = metrics.fetch("S") == "C"
        pr_table = scope_changed ? PR_CHANGED : PR_UNCHANGED

        av  = AV.fetch(metrics.fetch("AV"))
        ac  = AC.fetch(metrics.fetch("AC"))
        pr  = pr_table.fetch(metrics.fetch("PR"))
        ui  = UI.fetch(metrics.fetch("UI"))
        c   = CIA.fetch(metrics.fetch("C"))
        i   = CIA.fetch(metrics.fetch("I"))
        a   = CIA.fetch(metrics.fetch("A"))

        iss = 1 - ((1 - c) * (1 - i) * (1 - a))
        impact = if scope_changed
          (7.52 * (iss - 0.029)) - (3.25 * ((iss - 0.02)**15))
        else
          6.42 * iss
        end
        return 0.0 if impact <= 0

        exploitability = 8.22 * av * ac * pr * ui
        raw = impact + exploitability
        raw *= 1.08 if scope_changed
        round_up([raw, 10.0].min)
      end

      sig { params(vector: String).returns(T.nilable(Symbol)) }
      def self.severity(vector)
        score = base_score(vector)
        return if score.nil?

        if score >= 9.0 then :critical
        elsif score >= 7.0 then :high
        elsif score >= 4.0 then :medium
        elsif score > 0.0 then :low
        end
      end

      SUPPORTED_PREFIXES = %w[CVSS:3.0 CVSS:3.1].freeze
      private_constant :SUPPORTED_PREFIXES

      sig { params(vector: String).returns(T.nilable(T::Hash[String, String])) }
      private_class_method def self.parse(vector)
        parts = vector.split("/")
        return unless SUPPORTED_PREFIXES.include?(parts.shift)

        metrics = parts.to_h do |part|
          pair = part.split(":", 2)
          [pair[0] || "", pair[1] || ""]
        end
        return unless BASE_METRICS.all? { |m| metrics.key?(m) }
        return unless valid_values?(metrics)

        metrics
      end

      sig { params(metrics: T::Hash[String, String]).returns(T::Boolean) }
      private_class_method def self.valid_values?(metrics)
        AV.key?(metrics.fetch("AV")) &&
          AC.key?(metrics.fetch("AC")) &&
          PR_UNCHANGED.key?(metrics.fetch("PR")) &&
          UI.key?(metrics.fetch("UI")) &&
          %w[U C].include?(metrics.fetch("S")) &&
          CIA.key?(metrics.fetch("C")) &&
          CIA.key?(metrics.fetch("I")) &&
          CIA.key?(metrics.fetch("A"))
      end

      # CVSS v3.x "Roundup" (spec Appendix A).
      sig { params(value: Float).returns(Float) }
      private_class_method def self.round_up(value)
        int = (value * 100_000).round
        return int / 100_000.0 if (int % 10_000).zero?

        ((int / 10_000) + 1) / 10.0
      end
    end
  end
end
