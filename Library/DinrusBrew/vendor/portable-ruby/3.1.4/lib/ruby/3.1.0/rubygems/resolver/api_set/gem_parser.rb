# frozen_string_literal: true

class Gem::Resolver::APISet::GemParser
  def parse(line)
    version_and_platform, rest = line.split(" ", 2)
    version, platform = version_and_platform.split("-", 2)
    dependencies, requirements = rest.split("|", 2).map {|s| s.split(",") } if rest
    dependencies = dependencies ? dependencies.map {|d| parse_dependency(d) } : []
    requirements = requirements ? requirements.map {|d| parse_dependency(d) } : []
    [version, platform, dependencies, requirements]
  end

  private

  def parse_dependency(string)
    dependency = string.split(":")
    dependency[-1] = dependency[-1].split("&") if dependency.size > 1
    dependency
  end
end
