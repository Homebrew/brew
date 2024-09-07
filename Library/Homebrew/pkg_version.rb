# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "version"

# Combination of a version and a revision.
class PkgVersion
  include Comparable
  extend Forwardable

  REGEX = /\A(.+?)(?:_(\d+))?\z/
  private_constant :REGEX

  attr_reader :version, :revision

  delegate [:major, :minor, :patch, :major_minor, :major_minor_patch] => :version

  def self.parse(path)
    _, version, revision = *path.match(REGEX)
    version = Version.new(version)
    new(version, revision.to_i)
  end

  def initialize(version, revision)
    @version = version
    @revision = revision
  end

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

  def <=>(other)
    return unless other.is_a?(PkgVersion)

    version_comparison = (version <=> other.version)
    return if version_comparison.nil?

    version_comparison.nonzero? || revision <=> other.revision
  end
  alias eql? ==

  def hash
    [version, revision].hash
  end
end
