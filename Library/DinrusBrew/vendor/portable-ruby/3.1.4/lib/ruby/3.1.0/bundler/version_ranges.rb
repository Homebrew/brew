# frozen_string_literal: true

module Bundler
  module VersionRanges
    NEq = Struct.new(:version)
    ReqR = Struct.new(:left, :right)
    class ReqR
      Endpoint = Struct.new(:version, :inclusive) do
        def <=>(other)
          if version.equal?(INFINITY)
            return 0 if other.version.equal?(INFINITY)
            return 1
          elsif other.version.equal?(INFINITY)
            return -1
          end

          comp = version <=> other.version
          return comp unless comp.zero?

          if inclusive && !other.inclusive
            1
          elsif !inclusive && other.inclusive
            -1
          else
            0
          end
        end
      end

      def to_s
        "#{left.inclusive ? "[" : "("}#{left.version}, #{right.version}#{right.inclusive ? "]" : ")"}"
      end
      INFINITY = begin
        inf = Object.new
        def inf.to_s
          "∞"
        end
        def inf.<=>(other)
          return 0 if other.equal?(self)
          1
        end
        inf.freeze
      end
      ZERO = Gem::Version.new("0.a")

      def cover?(v)
        return false if left.inclusive && left.version > v
        return false if !left.inclusive && left.version >= v

        if right.version != INFINITY
          return false if right.inclusive && right.version < v
          return false if !right.inclusive && right.version <= v
        end

        true
      end

      def empty?
        left.version == right.version && !(left.inclusive && right.inclusive)
      end

      def single?
        left.version == right.version
      end

      def <=>(other)
        return -1 if other.equal?(INFINITY)

        comp = left <=> other.left
        return comp unless comp.zero?

        right <=> other.right
      end

      UNIVERSAL = ReqR.new(ReqR::Endpoint.new(Gem::Version.new("0.a"), true), ReqR::Endpoint.new(ReqR::INFINITY, false)).freeze
    end

    def self.for_many(requirements)
      requirements = requirements.map(&:requirements).flatten(1).map {|r| r.join(" ") }
      requirements << ">= 0.a" if requirements.empty?
      requirement = Gem::Requirement.new(requirements)
      self.for(requirement)
    end

    def self.for(requirement)
      ranges = requirement.requirements.map do |op, v|
        case op
        when "=" then ReqR.new(ReqR::Endpoint.new(v, true), ReqR::Endpoint.new(v, true))
        when "!=" then NEq.new(v)
        when ">=" then ReqR.new(ReqR::Endpoint.new(v, true), ReqR::Endpoint.new(ReqR::INFINITY, false))
        when ">" then ReqR.new(ReqR::Endpoint.new(v, false), ReqR::Endpoint.new(ReqR::INFINITY, false))
        when "<" then ReqR.new(ReqR::Endpoint.new(ReqR::ZERO, true), ReqR::Endpoint.new(v, false))
        when "<=" then ReqR.new(ReqR::Endpoint.new(ReqR::ZERO, true), ReqR::Endpoint.new(v, true))
        when "~>" then ReqR.new(ReqR::Endpoint.new(v, true), ReqR::Endpoint.new(v.bump, false))
        else raise "unknown version op #{op} in requirement #{requirement}"
        end
      end.uniq
      ranges, neqs = ranges.partition {|r| !r.is_a?(NEq) }

      [ranges.sort, neqs.map(&:version)]
    end

    def self.empty?(ranges, neqs)
      !ranges.reduce(ReqR::UNIVERSAL) do |last_range, curr_range|
        next false unless last_range
        next false if curr_range.single? && neqs.include?(curr_range.left.version)
        next curr_range if last_range.right.version == ReqR::INFINITY
        case last_range.right.version <=> curr_range.left.version
        # higher
        when 1 then next ReqR.new(curr_range.left, last_range.right)
        # equal
        when 0
          if last_range.right.inclusive && curr_range.left.inclusive && !neqs.include?(curr_range.left.version)
            ReqR.new(curr_range.left, [curr_range.right, last_range.right].max)
          end
        # lower
        when -1 then next false
        end
      end
    end
  end
end
