# frozen_string_literal: true

module Bundler
  class Resolver
    #
    # Represents a gem being resolved, in a format PubGrub likes.
    #
    # The class holds the following information:
    #
    # * Platforms this gem will be resolved on.
    # * The locked version of this gem resolution should favor (if any).
    # * Whether the gem should be unlocked to its latest version.
    # * The dependency explicit set in the Gemfile for this gem (if any).
    #
    class Package
      attr_reader :name, :platforms, :dependency, :locked_version

      def initialize(name, platforms, locked_specs:, unlock:, prerelease: false, prefer_local: false, dependency: nil)
        @name = name
        @platforms = platforms
        @locked_version = locked_specs[name].first&.version
        @unlock = unlock
        @dependency = dependency || Dependency.new(name, @locked_version)
        @top_level = !dependency.nil?
        @prerelease = @dependency.prerelease? || @locked_version&.prerelease? || prerelease ? :consider_first : :ignore
        @prefer_local = prefer_local
      end

      def platform_specs(specs)
        platforms.map {|platform| GemHelpers.select_best_platform_match(specs, platform, prefer_locked: !unlock?) }
      end

      def to_s
        @name.delete("\0")
      end

      def root?
        false
      end

      def top_level?
        @top_level
      end

      def meta?
        @name.end_with?("\0")
      end

      def ==(other)
        self.class == other.class && @name == other.name
      end

      def hash
        @name.hash
      end

      def unlock?
        @unlock.empty? || @unlock.include?(name)
      end

      def ignores_prereleases?
        @prerelease == :ignore
      end

      def prerelease_specified?
        @prerelease == :consider_first
      end

      def consider_prereleases!
        @prerelease = :consider_last
      end

      def prefer_local?
        @prefer_local
      end

      def consider_remote_versions!
        @prefer_local = false
      end

      def force_ruby_platform?
        @dependency.force_ruby_platform
      end

      def current_platform?
        @dependency.current_platform?
      end
    end
  end
end
