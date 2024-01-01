# typed: strict
# frozen_string_literal: true

module Homebrew
  module Livecheck
    # A formula or cask version, split into its component sub-versions.
    #
    # @api private
    class LivecheckVersion
      include Comparable

      sig {
        params(package_or_resource: T.any(Formula, Cask::Cask, Resource), version: Version).returns(LivecheckVersion)
      }
      def self.create(package_or_resource, version)
        versions = case package_or_resource
        when Formula, Resource
          [version]
        when Cask::Cask
          version.to_s.split(",").map { |s| Version.new(s) }
        else
          T.absurd(package_or_resource)
        end
        new(versions)
      end

      sig { returns(T::Array[Version]) }
      attr_reader :versions

      sig { params(versions: T::Array[Version]).void }
      def initialize(versions)
        @versions = versions
      end

      sig { params(other: T.untyped).returns(T.nilable(Integer)) }
      def <=>(other)
        return unless other.is_a?(LivecheckVersion)

        lversions = versions
        rversions = other.versions
        max = [lversions.count, rversions.count].max
        l = r = 0

        while l < max
          a = lversions[l] || Version::NULL
          b = rversions[r] || Version::NULL

          if a == b
            l += 1
            r += 1
            next
          elsif !a.null? && b.null?
            return 1 if a > Version::NULL

            l += 1
          elsif a.null? && !b.null?
            return -1 if b > Version::NULL

            r += 1
          else
            return a <=> b
          end
        end

        0
      end
    end
  end
end
