# typed: strict
# frozen_string_literal: true

require "vulns/cached_feed"
require "vulns/vulnerability"

module Homebrew
  module Vulns
    # Loader for the CPAN Security Advisory database.
    # Source: https://github.com/briandfoy/cpan-security-advisory
    #
    # The upstream repository ships a compiled `cpan-security-advisory.json`
    # keyed on CPAN distribution name. This class fetches and caches that file
    # and exposes advisories per distribution. Evaluating `affected_versions`
    # range strings against a formula version is left to {Vulns::Match}.
    class CPANSec < CachedFeed
      DATA_URL = "https://raw.githubusercontent.com/briandfoy/cpan-security-advisory/" \
                 "master/cpan-security-advisory.json"

      sig { override.returns(String) }
      def self.data_url = DATA_URL

      sig { override.returns(String) }
      def self.cache_filename = "cpansa.json"

      Advisory = Struct.new(
        :id, :cves, :affected_versions, :fixed_versions,
        :severity, :description, :references, :reported,
        keyword_init: true
      )

      sig { override.params(data: T.anything).void }
      def initialize(data)
        super
        raise Error, "CPANSA data is not a JSON object" unless (top = as_hash(data))
        raise Error, "CPANSA data missing 'dists' key" unless (dists = as_hash(top["dists"]))

        @dists = T.let(dists, T::Hash[String, T.untyped])
        @meta = T.let(as_hash(top["meta"]) || {}, T::Hash[String, T.untyped])
      end

      sig { returns(T::Hash[String, T.untyped]) }
      attr_reader :meta

      sig { returns(T::Array[String]) }
      def distributions
        @dists.keys
      end

      sig { params(distribution: String).returns(T::Array[Advisory]) }
      def advisories_for(distribution)
        entry = @dists[distribution]
        return [] unless entry.is_a?(Hash)

        Array(entry["advisories"]).filter_map { |a| build_advisory(a) if a.is_a?(Hash) }
      end

      # CPANSA constraints: each `affected_versions` array entry is a
      # comma-joined AND of `<`/`<=`/`>`/`>=`/`==`/`=`/bare-version terms; the
      # array is an OR of those. `fixed_versions` uses the same grammar.
      # Compared with {Version}; Perl's decimal-vs-dotted equivalence
      # (`1.002003` == `v1.2.3`) is not modelled since homebrew-core CPAN
      # formulae uniformly use the decimal form.
      sig { params(advisory: Advisory, version: String).returns(Vulnerability::RangeStatus) }
      def self.range_status(advisory, version)
        target = Version.new(version.sub(/\Av/i, ""))
        affected = advisory.affected_versions.empty? ||
                   advisory.affected_versions.any? { |c| satisfies?(target, c) }
        bounds = advisory.fixed_versions.flat_map { |c| lower_bounds(c) }
        if affected
          fixed_in = bounds.select { |v| target < v }.min&.to_s
          Vulnerability::RangeStatus.new(state: :affected, fixed_in:).freeze
        elsif advisory.fixed_versions.any? { |c| satisfies?(target, c) }
          fixed_in = bounds.select { |v| target >= v }.max&.to_s
          Vulnerability::RangeStatus.new(state: :fixed, fixed_in:).freeze
        else
          Vulnerability::RangeStatus.new(state: :not_applicable, fixed_in: nil).freeze
        end
      end

      CONSTRAINT = /\A\s*(<=|>=|==|<|>|=)?\s*v?(\d[\w.]*)\s*\z/
      private_constant :CONSTRAINT

      LOWER_BOUND_OPS = [">=", ">", "==", "=", nil].freeze
      private_constant :LOWER_BOUND_OPS

      sig { params(target: Version, conjunction: String).returns(T::Boolean) }
      def self.satisfies?(target, conjunction)
        conjunction.split(",").all? do |term|
          match = term.match(CONSTRAINT)
          bound_string = match[2] if match
          next false if match.nil? || bound_string.nil?

          bound = Version.new(bound_string)
          case match[1]
          when "<"  then target < bound
          when "<=" then target <= bound
          when ">"  then target > bound
          when ">=" then target >= bound
          else target == bound
          end
        end
      end

      sig { params(conjunction: String).returns(T::Array[Version]) }
      def self.lower_bounds(conjunction)
        conjunction.split(",").filter_map do |term|
          match = term.match(CONSTRAINT)
          next if match.nil? || LOWER_BOUND_OPS.exclude?(match[1])

          bound_string = match[2]
          Version.new(bound_string) unless bound_string.nil?
        end
      end

      sig { params(raw: T::Hash[String, T.untyped]).returns(T.nilable(Advisory)) }
      def build_advisory(raw)
        id = raw["id"]
        return if id.nil?

        Advisory.new(
          id:,
          cves:              Array(raw["cves"]).map(&:to_s),
          affected_versions: Array(raw["affected_versions"]).map(&:to_s),
          fixed_versions:    Array(raw["fixed_versions"]).map(&:to_s),
          severity:          raw["severity"],
          description:       raw["description"],
          references:        Array(raw["references"]).map(&:to_s),
          reported:          raw["reported"],
        ).freeze
      end
    end
  end
end
