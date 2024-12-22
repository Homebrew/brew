# typed: strict
# frozen_string_literal: true

require "version"

# Combination of a version and a revision.
class PkgVersion
  include Comparable
  extend Forwardable

  REGEX = /\A(.+?)(?:_(\d+))?\z/
  private_constant :REGEX

  sig { returns(Version) }
  attr_reader :version

  sig { returns(Integer) }
  attr_reader :revision

  delegate [:major, :minor, :patch, :major_minor, :major_minor_patch] => :version

  sig { params(path: String).returns(PkgVersion) }
  def self.parse(path)
    _, version, revision = *path.match(REGEX)
    version = Version.new(version.to_s)
    new(version, revision.to_i)
  end

  sig { params(version: Version, revision: Integer).void }
  def initialize(version, revision)
    @version = T.let(version, Version)
    @revision = T.let(revision, Integer)
  end

  sig { returns(T::Boolean) }
  def head?
    version.head?
  end

  sig { returns(String) }
  def to_str
    if revision.positive?
      "#{version}_#{revision}"
    else
      version.to_s
    end
  end

  sig { returns(String) }
  def to_s = to_str

  sig { params(other: PkgVersion).returns(T.nilable(Integer)) }
  def <=>(other)
    version_comparison = (version <=> other.version)
    return if version_comparison.nil?

    version_comparison.nonzero? || revision <=> other.revision
  end
  alias eql? ==

  sig { returns(Integer) }
  def hash
    [version, revision].hash
  end
end
