# frozen_string_literal: true

module Bundler
  # This class contains all of the logic for determining the next version of a
  # Gem to update to based on the requested level (patch, minor, major).
  # Primarily designed to work with Resolver which will provide it the list of
  # available dependency versions as found in its index, before returning it to
  # to the resolution engine to select the best version.
  class GemVersionPromoter
    DEBUG = ENV["BUNDLER_DEBUG_RESOLVER"] || ENV["DEBUG_RESOLVER"]

    attr_reader :level, :locked_specs, :unlock_gems

    # By default, strict is false, meaning every available version of a gem
    # is returned from sort_versions. The order gives preference to the
    # requested level (:patch, :minor, :major) but in complicated requirement
    # cases some gems will by necessity by promoted past the requested level,
    # or even reverted to older versions.
    #
    # If strict is set to true, the results from sort_versions will be
    # truncated, eliminating any version outside the current level scope.
    # This can lead to unexpected outcomes or even VersionConflict exceptions
    # that report a version of a gem not existing for versions that indeed do
    # existing in the referenced source.
    attr_accessor :strict

    attr_accessor :prerelease_specified

    # Given a list of locked_specs and a list of gems to unlock creates a
    # GemVersionPromoter instance.
    #
    # @param locked_specs [SpecSet] All current locked specs. Unlike Definition
    #   where this list is empty if all gems are being updated, this should
    #   always be populated for all gems so this class can properly function.
    # @param unlock_gems [String] List of gem names being unlocked. If empty,
    #   all gems will be considered unlocked.
    # @return [GemVersionPromoter]
    def initialize(locked_specs = SpecSet.new([]), unlock_gems = [])
      @level = :major
      @strict = false
      @locked_specs = locked_specs
      @unlock_gems = unlock_gems
      @sort_versions = {}
      @prerelease_specified = {}
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

    # Given a Dependency and an Array of Specifications of available versions for a
    # gem, this method will return the Array of Specifications sorted (and possibly
    # truncated if strict is true) in an order to give preference to the current
    # level (:major, :minor or :patch) when resolution is deciding what versions
    # best resolve all dependencies in the bundle.
    # @param dep [Dependency] The Dependency of the gem.
    # @param spec_groups [Specification] An array of Specifications for the same gem
    #    named in the @dep param.
    # @return [Specification] A new instance of the Specification Array sorted and
    #    possibly filtered.
    def sort_versions(dep, spec_groups)
      @sort_versions[dep] ||= begin
        gem_name = dep.name

        # An Array per version returned, different entries for different platforms.
        # We only need the version here so it's ok to hard code this to the first instance.
        locked_spec = locked_specs[gem_name].first

        if strict
          filter_dep_specs(spec_groups, locked_spec)
        else
          sort_dep_specs(spec_groups, locked_spec)
        end
      end
    end

    def reset
      @sort_versions = {}
    end

    # @return [bool] Convenience method for testing value of level variable.
    def major?
      level == :major
    end

    # @return [bool] Convenience method for testing value of level variable.
    def minor?
      level == :minor
    end

    private

    def filter_dep_specs(spec_groups, locked_spec)
      res = spec_groups.select do |spec_group|
        if locked_spec && !major?
          gsv = spec_group.version
          lsv = locked_spec.version

          must_match = minor? ? [0] : [0, 1]

          matches = must_match.map {|idx| gsv.segments[idx] == lsv.segments[idx] }
          matches.uniq == [true] ? (gsv >= lsv) : false
        else
          true
        end
      end

      sort_dep_specs(res, locked_spec)
    end

    def sort_dep_specs(spec_groups, locked_spec)
      @locked_version = locked_spec&.version
      @gem_name = locked_spec&.name

      result = spec_groups.sort do |a, b|
        @a_ver = a.version
        @b_ver = b.version

        unless @gem_name && @prerelease_specified[@gem_name]
          a_pre = @a_ver.prerelease?
          b_pre = @b_ver.prerelease?

          next -1 if a_pre && !b_pre
          next  1 if b_pre && !a_pre
        end

        if major?
          @a_ver <=> @b_ver
        elsif either_version_older_than_locked
          @a_ver <=> @b_ver
        elsif segments_do_not_match(:major)
          @b_ver <=> @a_ver
        elsif !minor? && segments_do_not_match(:minor)
          @b_ver <=> @a_ver
        else
          @a_ver <=> @b_ver
        end
      end
      post_sort(result)
    end

    def either_version_older_than_locked
      @locked_version && (@a_ver < @locked_version || @b_ver < @locked_version)
    end

    def segments_do_not_match(level)
      index = [:major, :minor].index(level)
      @a_ver.segments[index] != @b_ver.segments[index]
    end

    def unlocking_gem?
      unlock_gems.empty? || (@gem_name && unlock_gems.include?(@gem_name))
    end

    # Specific version moves can't always reliably be done during sorting
    # as not all elements are compared against each other.
    def post_sort(result)
      # default :major behavior in Bundler does not do this
      return result if major?
      if unlocking_gem? || @locked_version.nil?
        result
      else
        move_version_to_end(result, @locked_version)
      end
    end

    def move_version_to_end(result, version)
      move, keep = result.partition {|s| s.version.to_s == version.to_s }
      keep.concat(move)
    end
  end
end
