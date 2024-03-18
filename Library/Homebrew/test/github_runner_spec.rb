# frozen_string_literal: true

require "github_runner"

RSpec.describe GitHubRunner do
  let(:runner) do
    spec = MacOSRunnerSpec.new(name: "macOS 11-arm64", runner: "11-arm64", timeout: 90, cleanup: true)
    version = MacOSVersion.new("11")
    described_class.new(platform: :macos, arch: :arm64, spec:, macos_version: version)
  end

  it "has immutable attributes" do
    [:platform, :arch, :spec, :macos_version].each do |attribute|
      expect(runner.respond_to?(:"#{attribute}=")).to be(false)
    end
  end

  it "is inactive by default" do
    expect(runner.active).to be(false)
  end

  describe "#macos?" do
    it "returns true if the runner is a macOS runner" do
      expect(runner.macos?).to be(true)
    end
  end

  describe "#linux?" do
    it "returns false if the runner is a macOS runner" do
      expect(runner.linux?).to be(false)
    end
  end
end
