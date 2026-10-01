# typed: strict
# frozen_string_literal: true

require "cask/cask"
require "cask/ci/check"

RSpec.describe Cask::CI::Check do
  sig { returns(Cask::CI::Check::Snapshot) }
  let(:empty_snapshot) do
    {
      installed_apps:       [],
      installed_kexts:      [],
      installed_pkgs:       [],
      installed_launchjobs: [],
      loaded_launchjobs:    [],
    }
  end

  sig { returns(Cask::Cask) }
  def cask
    Cask::Cask.new("cask-ci-test")
  end

  it "returns no errors for an unchanged snapshot" do
    expect(described_class.errors(empty_snapshot, empty_snapshot, cask:)).to be_empty
  end

  it "reports applications left installed" do
    after = empty_snapshot.merge(installed_apps: ["/Applications/Cask CI Test.app"])

    expect(described_class.errors(empty_snapshot, after, cask:).first)
      .to include("Some applications are still installed", "/Applications/Cask CI Test.app")
  end

  it "reports launch jobs left installed" do
    after = empty_snapshot.merge(installed_launchjobs: ["com.example.cask-ci-test"])

    expect(described_class.errors(empty_snapshot, after, cask:).first)
      .to include("Some launch jobs are still installed", "com.example.cask-ci-test")
  end

  it "ignores known Apple and Google running jobs" do
    after = empty_snapshot.merge(
      loaded_launchjobs: ["application.com.apple.Safari.123", "application.com.google.GoogleUpdater.123"],
    )

    expect(described_class.errors(empty_snapshot, after, cask:)).to be_empty
  end

  it "ignores Firefox opened by non-Firefox casks" do
    after = empty_snapshot.merge(loaded_launchjobs: ["application.org.mozilla.firefox.123"])

    expect(described_class.errors(empty_snapshot, after, cask:)).to be_empty
  end

  it "honours quit wildcard directives" do
    cask = Cask::Cask.new("cask-ci-test") do
      uninstall quit: "com.example.*"
    end
    after = empty_snapshot.merge(loaded_launchjobs: ["application.com.example.CaskCi.123"])

    expect(described_class.errors(empty_snapshot, after, cask:)).to be_empty
  end

  it "honours unanchored case-sensitive launchctl directives" do
    cask = Cask::Cask.new("cask-ci-test") do
      uninstall launchctl: "com.example.*"
    end
    after = empty_snapshot.merge(loaded_launchjobs: ["prefix.com.example.service.suffix"])

    expect(described_class.errors(empty_snapshot, after, cask:)).to be_empty
  end

  it "anchors quit directives and ignores case" do
    ids = ["com.Example.CaskCi", "prefix.com.example.caskci"]

    expect(described_class.reject_matching(ids, "com.example.*")).to eq(["prefix.com.example.caskci"])
  end

  it "supports unanchored case-sensitive matching" do
    ids = ["prefix.com.example.service.suffix", "prefix.com.Example.service.suffix"]

    expect(described_class.reject_matching(ids, "com.example.*", anchored: false, ignore_case: false))
      .to eq(["prefix.com.Example.service.suffix"])
  end
end
