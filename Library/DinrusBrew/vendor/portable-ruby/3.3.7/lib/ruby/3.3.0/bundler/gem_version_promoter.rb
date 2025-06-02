# frozen_string_literal: true

module Bundler
  # This class contains all of the logic for determining the next version of a
  # Gem to update to based on the requested level (patch, minor, major).
  # Primarily designed to work with Resolver which will provide it the list of
  # available dependency versions as found in its index, before returning it to
  # to the resolution engine to select the best version.
  class GemVersionPromoter
    attr_reader :level
    attr_accessor :pre

    # By default, strict is false, meaning every available version of a gem
    # is returned from sort_versions. The order gives preference to the
    # requested level (:patch, :minor, :major) but in complicated requirement
    # cases some gems will by necessity be promoted past the requested level,
    # or even reverted to older versions.
    #
    # If strict is set to true, the results from sort_versions will be
    # truncated, eliminating any version outside the current level scope.
    # This can lead to unexpected outcomes or even VersionConflict exceptions
    # that report a version of a gem not existing for versions that indeed do
    # existing in the referenced source.
    attr_accessor :strict

    # Creates a GemVersionPromoter instance.
    #
    # @return [GemVersionPromoter]
    def initialize
      @level = :major
      @strict = false
      @pre = false
    end

    # @param value [Symbol] One of three Symbols: :major, :minor or :patch.
    def level=(value)
      v = case value
          when String, Symbol
            value.to_sym
      end

      raise ArgumentError, "Unexpected level #{v}. Must be :major, :minor or :patch" unless [:major, :minor, :patch].include?(v)
      @level = v
    end

    # Given a Resolver::Package and an Array of Specifications of available
    # versions for a gem, this method will return the Array of Specifications
    # sorted in an order to give preference to the current level (:major, :minor
    # or :patch) when resolution is deciding what versions best resolve all
    # dependencies in the bundle.
    # @param package [Resolver::Package] The package being resolved.
    # @param specs [Specification] An array of Specifications for the package.
    # @return [Specification] A new instance of the Specification Array sorted.
    def sort_versions(package, specs)
      locked_version = package.locked_version

      result = specs.sort do |a, b|
        unless package.prerelease_specified? || pre?
          a_pre = a.prerelease?
          b_pre = b.prerelease?

          next 1 if a_pre && !b_pre
          next -1 if b_pre && !a_pre
        end

        if major? || locked_version.nil?
          b <=> a
        elsif either_version_older_than_locked?(a, b, locked_version)
          b <=> a
        elsif segments_do_not_match?(a, b, :major)
          a <=> b
        elsif !minor? && segments_do_not_match?(a, b, :minor)
          a <=> b
        else
          b <=> a
        end
      end
      post_sort(result, package.unlock?, locked_version)
    end

    # @return [bool] Convenience method for testing value of level variable.
    def major?
      level == :major
    end

    # @return [bool] Convenience method for testing value of level variable.
    def minor?
      level == :minor
    end

    # @return [bool] Convenience method for testing value of pre variable.
    def pre?
      pre == true
    end

    # Given a Resolver::Package and an Array of Specifications of available
    # versions for a gem, this method will truncate the Array if strict
    # is true. That means filtering out downgrades from the version currently
    # locked, and filtering out upgrades that go past the selected level (major,
    # minor, or patch).
    # @param package [Resolver::Package] The package being resolved.
    # @param specs [Specification] An array of Specifications for the package.
    # @return [Specification] A new instance of the Specification Array
    #   truncated.
    def filter_versions(package, specs)
      return specs unless strict

      locked_version = package.locked_version
      return specs if locked_version.nil? || major?

      specs.select do |spec|
        gsv = spec.version

        must_match = minor? ? [0] : [0, 1]

        all_match = must_match.all? {|idx| gsv.segments[idx] == locked_version.segments[idx] }
        all_match && gsv >= locked_version
      end
    end

    private

    def either_version_older_than_locked?(a, b, locked_version)
      a.version < locked_version || b.version < locked_version
    end

    def segments_do_not_match?(a, b, level)
      index = [:major, :minor].index(level)
      a.segments[index] != b.segments[index]
    end

    # Specific version moves can't always reliably be done during sorting
    # as not all elements are compared against each other.
    def post_sort(result, unlock, locked_version)
      # default :major behavior in Bundler does not do this
      return result if major?
      if unlock || locked_version.nil?
        result
      else
        move_version_to_beginning(result, locked_version)
      end
    end

    def move_version_to_beginning(result, version)
      move, keep = result.partition {|s| s.version.to_s == version.to_s }
      move.concat(keep)
    end
  end
end
