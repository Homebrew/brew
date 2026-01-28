# typed: true
# frozen_string_literal: true

class FailballOfflineInstall < Formula
  def initialize(name = "failball_offline_install", path = Pathname.new(__FILE__).expand_path, spec = :stable,
                 alias_path: nil, tap: nil, force_bottle: false)
    super
  end

  DSL_PROC = proc do
    url "file://#{TEST_FIXTURE_DIR}/tarballs/testball-0.1.tbz"
    sha256 TESTBALL_SHA256
    deny_network_access! :build
  end.freeze
  private_constant :DSL_PROC

  DSL_PROC.call

  def self.inherited(other)
    super
    other.instance_eval(&DSL_PROC)
  end

  def install
    system "curl", "example.org"

    prefix.install "bin"
    prefix.install "libexec"
    Dir.chdir "doc"
  end
end
