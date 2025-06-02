# frozen_string_literal: true

module Bundler::PubGrub
  class VersionRange
    attr_reader :min, :max, :include_min, :include_max

    alias_method :include_min?, :include_min
    alias_method :include_max?, :include_max

    class Empty < VersionRange
      undef_method :min, :max
      undef_method :include_min, :include_min?
      undef_method :include_max, :include_max?

      def initialize
      end

      def empty?
        true
      end

      def eql?(other)
        other.empty?
      end

      def hash
        [].hash
      end

      def intersects?(_)
        false
      end

      def intersect(other)
        self
      end

      def allows_all?(other)
        other.empty?
      end

      def include?(_)
        false
      end

      def any?
        false
      end

      def to_s
        "(no versions)"
      end

      def ==(other)
        other.class == self.class
      end

      def invert
        VersionRange.any
      end

      def select_versions(_)
        []
      end
    end

    EMPTY = Empty.new
    Empty.singleton_class.undef_method(:new)

    def self.empty
      EMPTY
    end

    def self.any
      new
    end

    def initialize(min: nil, max: nil, include_min: false, include_max: false, name: nil)
      @min = min
      @max = max
      @include_min = include_min
      @include_max = include_max
      @name = name
    end

    def hash
      @hash ||= min.hash ^ max.hash ^ include_min.hash ^ include_max.hash
    end

    def eql?(other)
      if other.is_a?(VersionRange)
        !other.empty? &&
          min.eql?(other.min) &&
          max.eql?(other.max) &&
          include_min.eql?(other.include_min) &&
          include_max.eql?(other.include_max)
      else
        ranges.eql?(other.ranges)
      end
    end

    def ranges
      [self]
    end

    def include?(version)
      compare_version(version) == 0
    end

    # Partitions passed versions into [lower, within, higher]
    #
    # versions must be sorted
    def partition_versions(versions)
      min_index =
        if !min || versions.empty?
          0
        elsif include_min?
          (0..versions.size).bsearch { |i| versions[i].nil? || versions[i] >= min }
        else
          (0..versions.size).bsearch { |i| versions[i].nil? || versions[i] > min }
        end

      lower = versions.slice(0, min_index)
      versions = versions.slice(min_index, versions.size)

      max_index =
        if !max || versions.empty?
          versions.size
        elsif include_max?
          (0..versions.size).bsearch { |i| versions[i].nil? || versions[i] > max }
        else
          (0..versions.size).bsearch { |i| versions[i].nil? || versions[i] >= max }
        end

      [
        lower,
        versions.slice(0, max_index),
        versions.slice(max_index, versions.size)
      ]
    end

    # Returns versions which are included by this range.
    #
    # versions must be sorted
    def select_versions(versions)
      return versions if any?

      partition_versions(versions)[1]
    end

    def compare_version(version)
      if min
        case version <=> min
        when -1
          return -1
        when 0
          return -1 if !include_min
        when 1
        end
      end

      if max
        case version <=> max
        when -1
        when 0
          return 1 if !include_max
        when 1
          return 1
        end
      end

      0
    end

    def strictly_lower?(other)
      return false if !max || !other.min

      case max <=> other.min
      when 0
        !include_max || !other.include_min
      when -1
        true
      when 1
        false
      end
    end

    def strictly_higher?(other)
      other.strictly_lower?(self)
    end

    def intersects?(other)
      return false if other.empty?
      return other.intersects?(self) if other.is_a?(VersionUnion)
      !strictly_lower?(other) && !strictly_higher?(other)
    end
    alias_method :allows_any?, :intersects?

    def intersect(other)
      return other if other.empty?
      return other.intersect(self) if other.is_a?(VersionUnion)

      min_range =
        if !min
          other
        elsif !other.min
          self
        else
          case min <=> other.min
          when 0
            include_min ? other : self
          when -1
            other
          when 1
            self
          end
        end

      max_range =
        if !max
          other
        elsif !other.max
          self
        else
          case max <=> other.max
          when 0
            include_max ? other : self
          when -1
            self
          when 1
            other
          end
        end

      if !min_range.equal?(max_range) && min_range.min && max_range.max
        case min_range.min <=> max_range.max
        when -1
        when 0
          if !min_range.include_min || !max_range.include_max
            return EMPTY
          end
        when 1
          return EMPTY
        end
      end

      VersionRange.new(
        min: min_range.min,
        include_min: min_range.include_min,
        max: max_range.max,
        include_max: max_range.include_max
      )
    end

    # The span covered by two ranges
    #
    # If self and other are contiguous, this builds a union of the two ranges.
    # (if they aren't you are probably calling the wrong method)
    def span(other)
      return self if other.empty?

      min_range =
        if !min
          self
        elsif !other.min
          other
        else
          case min <=> other.min
          when 0
            include_min ? self : other
          when -1
            self
          when 1
            other
          end
        end

      max_range =
        if !max
          self
        elsif !other.max
          other
        else
          case max <=> other.max
          when 0
            include_max ? self : other
          when -1
            other
          when 1
            self
          end
        end

      VersionRange.new(
        min: min_range.min,
        include_min: min_range.include_min,
        max: max_range.max,
        include_max: max_range.include_max
      )
    end

    def union(other)
      return other.union(self) if other.is_a?(VersionUnion)

      if contiguous_to?(other)
        span(other)
      else
        VersionUnion.union([self, other])
      end
    end

    def contiguous_to?(other)
      return false if other.empty?

      intersects?(other) ||
        (min == other.max && (include_min || other.include_max)) ||
        (max == other.min && (include_max || other.include_min))
    end

    def allows_all?(other)
      return true if other.empty?

      if other.is_a?(VersionUnion)
        return VersionUnion.new([self]).allows_all?(other)
      end

      return false if max && !other.max
      return false if min && !other.min

      if min
        case min <=> other.min
        when -1
        when 0
          return false if !include_min && other.include_min
        when 1
          return false
        end
      end

      if max
        case max <=> other.max
        when -1
          return false
        when 0
          return false if !include_max && other.include_max
        when 1
        end
      end

      true
    end

    def any?
      !min && !max
    end

    def empty?
      false
    end

    def to_s
      @name ||= constraints.join(", ")
    end

    def inspect
      "#<#{self.class} #{to_s}>"
    end

    def upper_invert
      return self.class.empty unless max

      VersionRange.new(min: max, include_min: !include_max)
    end

    def invert
      return self.class.empty if any?

      low = VersionRange.new(max: min, include_max: !include_min)
      high = VersionRange.new(min: max, include_min: !include_max)

      if !min
        high
      elsif !max
        low
      else
        low.union(high)
      end
    end

    def ==(other)
      self.class == other.class &&
        min == other.min &&
        max == other.max &&
        include_min == other.include_min &&
        include_max == other.include_max
    end

    private

    def constraints
      return ["any"] if any?
      return ["= #{min}"] if min.to_s == max.to_s

      c = []
      c << "#{include_min ? ">=" : ">"} #{min}" if min
      c << "#{include_max ? "<=" : "<"} #{max}" if max
      c
    end

  end
end
