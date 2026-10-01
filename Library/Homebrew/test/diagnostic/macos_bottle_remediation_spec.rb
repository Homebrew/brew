# typed: true
# frozen_string_literal: true

require "diagnostic"

RSpec.describe Homebrew::Diagnostic::Checks do
  subject(:checks) { described_class.new }

  describe "#macos_bottle_remediation" do
    it "recommends MacPorts binaries on outdated Intel macOS" do
      expect(checks.macos_bottle_remediation(MacOSVersion.new("13"), intel: true)).to eq <<~EOS
        Homebrew no longer builds bottles for this configuration.
        Consider MacPorts, which provides binary packages for this macOS version:
          https://www.macports.org
      EOS
    end

    it "recommends MacPorts binaries on Intel Sequoia" do
      expect(checks.macos_bottle_remediation(MacOSVersion.new("15.7"), intel: true))
        .to include("MacPorts")
    end

    it "explains bottle availability without recommending a replacement on Intel Tahoe" do
      expect(checks.macos_bottle_remediation(MacOSVersion.new("26.1"), intel: true)).to eq <<~EOS
        Homebrew no longer builds bottles for this configuration.
        Existing bottles may still work, but updated formulae may build from source.
      EOS
    end

    it "recommends MacPorts binaries on outdated Apple Silicon macOS" do
      expect(checks.macos_bottle_remediation(MacOSVersion.new("13"), intel: false))
        .to include("MacPorts")
    end

    it "does not recommend alternatives when Homebrew builds bottles" do
      expect(checks.macos_bottle_remediation(MacOSVersion.new("26"), intel: false)).to be_nil
    end

    it "does not assume binary availability on future Intel macOS versions" do
      expect(checks.macos_bottle_remediation(MacOSVersion.new("30"), intel: true)).to be_nil
    end

    it "does not recommend alternatives on pre-release Apple Silicon macOS" do
      expect(checks.macos_bottle_remediation(MacOSVersion.new("30"), intel: false)).to be_nil
    end
  end
end
