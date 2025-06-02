# frozen_string_literal: true

require_relative "spec_group"

module Bundler
  class Resolver
    #
    # This class is a PubGrub compatible "Version" class that takes Bundler
    # resolution complexities into account.
    #
    # Each Resolver::Candidate has a underlying `Gem::Version` plus a set of
    # platforms. For example, 1.1.0-x86_64-linux is a different resolution candidate
    # from 1.1.0 (generic). This is because different platform variants of the
    # same gem version can bring different dependencies, so they need to be
    # considered separately.
    #
    # Some candidates may also keep some information explicitly about the
    # package they refer to. These candidates are referred to as "canonical" and
    # are used when materializing resolution results back into RubyGems
    # specifications that can be installed, written to lock files, and so on.
    #
    class Candidate
      include Comparable

      attr_reader :version

      def initialize(version, group: nil, priority: -1)
        @spec_group = group || SpecGroup.new([])
        @version = Gem::Version.new(version)
        @priority = priority
      end

      def dependencies
        @spec_group.dependencies
      end

      def to_specs(package)
        return [] if package.meta?

        @spec_group.to_specs(package.force_ruby_platform?)
      end

      def prerelease?
        @version.prerelease?
      end

      def segments
        @version.segments
      end

      def sort_obj
        [@version, @priority]
      end

      def <=>(other)
        return unless other.is_a?(self.class)

        sort_obj <=> other.sort_obj
      end

      def ==(other)
        return unless other.is_a?(self.class)

        sort_obj == other.sort_obj
      end

      def eql?(other)
        return unless other.is_a?(self.class)

        sort_obj.eql?(other.sort_obj)
      end

      def hash
        sort_obj.hash
      end

      def to_s
        @version.to_s
      end
    end
  end
end
