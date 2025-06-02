# typed: true
# frozen_string_literal: true

class Failball < Formula
  def initialize(name = "failball", path = Pathname.new(__FILE__).expand_path, spec = :stable,
                 alias_path: nil, tap: nil, force_bottle: false)
    super
  end

  DSL_PROC = proc do
    url "file://#{TEST_FIXTURE_DIR}/tarballs/testball-0.1.tbz"
    sha256 TESTBALL_SHA256
  end.freeze
  private_constant :DSL_PROC

  DSL_PROC.call

  def self.inherited(other)
    super
    other.instance_eval(&DSL_PROC)
  end

  def install
    prefix.install "bin"
    prefix.install "libexec"

    # This should get marshalled into a BuildError.
    system "/usr/bin/false" if ENV["FAILBALL_BUILD_ERROR"]

    # This should get marshalled into a RuntimeError.
    raise "Something that isn't a build error happened!"
  end
end
