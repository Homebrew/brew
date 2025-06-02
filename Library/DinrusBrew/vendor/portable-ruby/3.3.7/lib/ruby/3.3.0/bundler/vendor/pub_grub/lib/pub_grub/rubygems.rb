module Bundler::PubGrub
  module RubyGems
    extend self

    def requirement_to_range(requirement)
      ranges = requirement.requirements.map do |(op, ver)|
        case op
        when "~>"
          name = "~> #{ver}"
          bump = ver.class.new(ver.bump.to_s + ".A")
          VersionRange.new(name: name, min: ver, max: bump, include_min: true)
        when ">"
          VersionRange.new(min: ver)
        when ">="
          VersionRange.new(min: ver, include_min: true)
        when "<"
          VersionRange.new(max: ver)
        when "<="
          VersionRange.new(max: ver, include_max: true)
        when "="
          VersionRange.new(min: ver, max: ver, include_min: true, include_max: true)
        when "!="
          VersionRange.new(min: ver, max: ver, include_min: true, include_max: true).invert
        else
          raise "bad version specifier: #{op}"
        end
      end

      ranges.inject(&:intersect)
    end

    def requirement_to_constraint(package, requirement)
      Bundler::PubGrub::VersionConstraint.new(package, range: requirement_to_range(requirement))
    end

    def parse_range(dep)
      requirement_to_range(Gem::Requirement.new(dep))
    end

    def parse_constraint(package, dep)
      range = parse_range(dep)
      Bundler::PubGrub::VersionConstraint.new(package, range: range)
    end
  end
end
