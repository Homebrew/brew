# typed: strict
# frozen_string_literal: true

module Homebrew
  module Vulns
    # SemVer 2.0 comparison for OSV `SEMVER` ranges (https://semver.org/#spec-item-11).
    # Kept separate from `::Version`, whose ordering differs for prerelease and
    # build metadata. Minor/patch may be omitted; other spec violations return `nil`.
    module Semver
      CORE_SEGMENT = "(0|[1-9]\\d*)"
      private_constant :CORE_SEGMENT

      # A numeric identifier without a leading zero, or an alphanumeric
      # identifier (which may start with any digit).
      PRERELEASE_IDENTIFIER = "(?:0|[1-9]\\d*|\\d*[A-Za-z-][0-9A-Za-z-]*)"
      private_constant :PRERELEASE_IDENTIFIER

      BUILD_IDENTIFIER = "[0-9A-Za-z-]+"
      private_constant :BUILD_IDENTIFIER

      SEMVER_REGEX = /
        \A
        #{CORE_SEGMENT}(?:\.#{CORE_SEGMENT})?(?:\.#{CORE_SEGMENT})?
        (?:-(#{PRERELEASE_IDENTIFIER}(?:\.#{PRERELEASE_IDENTIFIER})*))?
        (?:\+#{BUILD_IDENTIFIER}(?:\.#{BUILD_IDENTIFIER})*)?
        \z
      /x
      private_constant :SEMVER_REGEX

      NUMERIC_IDENTIFIER = /\A\d+\z/
      private_constant :NUMERIC_IDENTIFIER

      sig { params(left: String, right: String).returns(T.nilable(Integer)) }
      def self.compare(left, right)
        a = parse(left)
        b = parse(right)
        return if a.nil? || b.nil?

        core = a.fetch(:core) <=> b.fetch(:core)
        return core unless core.zero?

        compare_prerelease(a.fetch(:prerelease), b.fetch(:prerelease))
      end

      sig { params(version: String).returns(T.nilable({ core: [Integer, Integer, Integer], prerelease: T::Array[String] })) }
      private_class_method def self.parse(version)
        match = version.strip.delete_prefix("v").delete_prefix("V").match(SEMVER_REGEX)
        return if match.nil?

        {
          core:       [match[1].to_i, match[2].to_i, match[3].to_i],
          prerelease: match[4]&.split(".") || [],
        }
      end

      sig { params(left: T::Array[String], right: T::Array[String]).returns(Integer) }
      private_class_method def self.compare_prerelease(left, right)
        return 0 if left.empty? && right.empty?
        return 1 if left.empty?
        return -1 if right.empty?

        left.zip(right) do |lhs, rhs|
          return 1 if rhs.nil?

          cmp = compare_identifier(lhs, rhs)
          return cmp unless cmp.zero?
        end
        (left.length == right.length) ? 0 : -1
      end

      sig { params(lhs: String, rhs: String).returns(Integer) }
      private_class_method def self.compare_identifier(lhs, rhs)
        lhs_numeric = lhs.match?(NUMERIC_IDENTIFIER)
        rhs_numeric = rhs.match?(NUMERIC_IDENTIFIER)

        # spec 11.4.3: numeric identifiers sort below alphanumeric
        return -1 if lhs_numeric && !rhs_numeric
        return 1 if !lhs_numeric && rhs_numeric

        if lhs_numeric
          lhs.to_i <=> rhs.to_i
        else
          T.must(lhs <=> rhs)
        end
      end
    end
  end
end
