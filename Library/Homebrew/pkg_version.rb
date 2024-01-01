# typed: true
# frozen_string_literal: true

require "version"

# Combination of a version and a revision.
#
# @api private
class PkgVersion
  include Comparable
  extend Forwardable

  REGEX = /\A(.+?)(?:_(\d+))?\z/.freeze
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

  def to_s
    if revision.positive?
      "#{version}_#{revision}"
    else
      version.to_s
    end
  end
  alias to_str to_s

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
