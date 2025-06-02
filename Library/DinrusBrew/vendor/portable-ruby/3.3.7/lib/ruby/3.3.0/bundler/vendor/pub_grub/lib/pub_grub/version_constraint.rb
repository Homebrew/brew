require_relative 'version_range'

module Bundler::PubGrub
  class VersionConstraint
    attr_reader :package, :range

    # @param package [Bundler::PubGrub::Package]
    # @param range [Bundler::PubGrub::VersionRange]
    def initialize(package, range: nil)
      @package = package
      @range = range
    end

    def hash
      package.hash ^ range.hash
    end

    def ==(other)
      package == other.package &&
        range == other.range
    end

    def eql?(other)
      package.eql?(other.package) &&
        range.eql?(other.range)
    end

    class << self
      def exact(package, version)
        range = VersionRange.new(min: version, max: version, include_min: true, include_max: true)
        new(package, range: range)
      end

      def any(package)
        new(package, range: VersionRange.any)
      end

      def empty(package)
        new(package, range: VersionRange.empty)
      end
    end

    def intersect(other)
      unless package == other.package
        raise ArgumentError, "Can only intersect between VersionConstraint of the same package"
      end

      self.class.new(package, range: range.intersect(other.range))
    end

    def union(other)
      unless package == other.package
        raise ArgumentError, "Can only intersect between VersionConstraint of the same package"
      end

      self.class.new(package, range: range.union(other.range))
    end

    def invert
      new_range = range.invert
      self.class.new(package, range: new_range)
    end

    def difference(other)
      intersect(other.invert)
    end

    def allows_all?(other)
      range.allows_all?(other.range)
    end

    def allows_any?(other)
      range.intersects?(other.range)
    end

    def subset?(other)
      other.allows_all?(self)
    end

    def overlap?(other)
      other.allows_any?(self)
    end

    def disjoint?(other)
      !overlap?(other)
    end

    def relation(other)
      if subset?(other)
        :subset
      elsif overlap?(other)
        :overlap
      else
        :disjoint
      end
    end

    def to_s(allow_every: false)
      if Package.root?(package)
        package.to_s
      elsif allow_every && any?
        "every version of #{package}"
      else
        "#{package} #{constraint_string}"
      end
    end

    def constraint_string
      if any?
        ">= 0"
      else
        range.to_s
      end
    end

    def empty?
      range.empty?
    end

    # Does this match every version of the package
    def any?
      range.any?
    end

    def inspect
      "#<#{self.class} #{self}>"
    end
  end
end
