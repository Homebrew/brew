# typed: strict
# frozen_string_literal: true

# Formula information drawn from an external `brew info --json` call.
class FormulaInfo
  # The whole info structure parsed from the JSON.
  sig { returns(T::Hash[String, T.untyped]) }
  attr_accessor :info

  sig { params(info: T::Hash[String, T.untyped]).void }
  def initialize(info)
    @info = info
  end

  sig { returns(T::Array[String]) }
  def bottle_tags
    return [] unless info["bottle"]["stable"]

    info["bottle"]["stable"]["files"].keys
  end

  sig { params(spec_type: Symbol).returns(Version) }
  def version(spec_type)
    version_str = info["versions"][spec_type.to_s]
    Version.new(version_str)
  end

  sig { params(spec_type: Symbol).returns(PkgVersion) }
  def pkg_version(spec_type = :stable)
    PkgVersion.new(version(spec_type), revision)
  end

  sig { returns(Integer) }
  def revision
    info["revision"]
  end
end
