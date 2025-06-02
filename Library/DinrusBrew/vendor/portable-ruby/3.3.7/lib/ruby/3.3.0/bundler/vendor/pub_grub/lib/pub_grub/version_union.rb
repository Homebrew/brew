# frozen_string_literal: true

module Bundler::PubGrub
  class VersionUnion
    attr_reader :ranges

    def self.normalize_ranges(ranges)
      ranges = ranges.flat_map do |range|
        range.ranges
      end

      ranges.reject!(&:empty?)

      return [] if ranges.empty?

      mins, ranges = ranges.partition { |r| !r.min }
      original_ranges = mins + ranges.sort_by { |r| [r.min, r.include_min ? 0 : 1] }
      ranges = [original_ranges.shift]
      original_ranges.each do |range|
        if ranges.last.contiguous_to?(range)
          ranges << ranges.pop.span(range)
        else
          ranges << range
        end
      end

      ranges
    end

    def self.union(ranges, normalize: true)
      ranges = normalize_ranges(ranges) if normalize

      if ranges.size == 0
        VersionRange.empty
      elsif ranges.size == 1
        ranges[0]
      else
        new(ranges)
      end
    end

    def initialize(ranges)
      raise ArgumentError unless ranges.all? { |r| r.instance_of?(VersionRange) }
      @ranges = ranges
    end

    def hash
      ranges.hash
    end

    def eql?(other)
      ranges.eql?(other.ranges)
    end

    def include?(version)
      !!ranges.bsearch {|r| r.compare_version(version) }
    end

    def select_versions(all_versions)
      versions = []
      ranges.inject(all_versions) do |acc, range|
        _, matching, higher = range.partition_versions(acc)
        versions.concat matching
        higher
      end
      versions
    end

    def intersects?(other)
      my_ranges = ranges.dup
      other_ranges = other.ranges.dup

      my_range = my_ranges.shift
      other_range = other_ranges.shift
      while my_range && other_range
        if my_range.intersects?(other_range)
          return true
        end

        if !my_range.max || other_range.empty? || (other_range.max && other_range.max < my_range.max)
          other_range = other_ranges.shift
        else
          my_range = my_ranges.shift
        end
      end
    end
    alias_method :allows_any?, :intersects?

    def allows_all?(other)
      my_ranges = ranges.dup

      my_range = my_ranges.shift

      other.ranges.all? do |other_range|
        while my_range
          break if my_range.allows_all?(other_range)
          my_range = my_ranges.shift
        end

        !!my_range
      end
    end

    def empty?
      false
    end

    def any?
      false
    end

    def intersect(other)
      my_ranges = ranges.dup
      other_ranges = other.ranges.dup
      new_ranges = []

      my_range = my_ranges.shift
      other_range = other_ranges.shift
      while my_range && other_range
        new_ranges << my_range.intersect(other_range)

        if !my_range.max || other_range.empty? || (other_range.max && other_range.max < my_range.max)
          other_range = other_ranges.shift
        else
          my_range = my_ranges.shift
        end
      end
      new_ranges.reject!(&:empty?)
      VersionUnion.union(new_ranges, normalize: false)
    end

    def upper_invert
      ranges.last.upper_invert
    end

    def invert
      ranges.map(&:invert).inject(:intersect)
    end

    def union(other)
      VersionUnion.union([self, other])
    end

    def to_s
      output = []

      ranges = self.ranges.dup
      while !ranges.empty?
        ne = []
        range = ranges.shift
        while !ranges.empty? && ranges[0].min.to_s == range.max.to_s
          ne << range.max
          range = range.span(ranges.shift)
        end

        ne.map! {|x| "!= #{x}" }
        if ne.empty?
          output << range.to_s
        elsif range.any?
          output << ne.join(', ')
        else
          output << "#{range}, #{ne.join(', ')}"
        end
      end

      output.join(" OR ")
    end

    def inspect
      "#<#{self.class} #{to_s}>"
    end

    def ==(other)
      self.class == other.class &&
        self.ranges == other.ranges
    end
  end
end
