# typed: true
# frozen_string_literal: true

require "bundle/trust"

RSpec.describe Homebrew::Bundle::Trust do
  before do
    described_class.reset!
  end

  describe ".trusted_entries" do
    it "delegates to Homebrew::Trust when wrapper mode is not forced" do
      allow(Homebrew::EnvConfig).to receive(:force_brew_wrapper).and_return(nil)
      expect(Homebrew::Trust).to receive(:trusted_entries).with(:formula).and_return(["user/tap/foo"])

      expect(described_class.trusted_entries(:formula)).to eq(["user/tap/foo"])
    end

    it "reads trusted entries through brew when wrapper mode is forced" do
      allow(Homebrew::EnvConfig).to receive(:force_brew_wrapper).and_return("/tmp/wrapper/brew")
      trust_json = <<~JSON
        {
          "taps": [],
          "formulae": ["user/tap/foo"],
          "casks": [],
          "commands": []
        }
      JSON

      expect(Utils).to receive(:safe_popen_read)
        .with(HOMEBREW_BREW_FILE, "trust", "--json=v1")
        .and_return(trust_json)

      expect(described_class.trusted_entries(:formula)).to eq(["user/tap/foo"])
    end
  end

  describe ".trusted?" do
    it "checks trusted taps through brew output when wrapper mode is forced" do
      allow(Homebrew::EnvConfig).to receive(:force_brew_wrapper).and_return("/tmp/wrapper/brew")
      trust_json = <<~JSON
        {
          "taps": ["https://gitlab.com/user/homebrew-tap"],
          "formulae": [],
          "casks": [],
          "commands": []
        }
      JSON

      allow(Utils).to receive(:safe_popen_read)
        .with(HOMEBREW_BREW_FILE, "trust", "--json=v1")
        .and_return(trust_json)

      tap = instance_double(Tap)
      allow(Tap).to receive(:fetch).with("user/tap").and_return(tap)
      allow(tap).to receive(:implicitly_trusted?).and_return(false)
      allow(tap).to receive(:matches_reference?).with("https://gitlab.com/user/homebrew-tap").and_return(true)

      expect(described_class.trusted?(:formula, "user/tap/foo")).to be(true)
    end
  end

  describe ".trust!" do
    it "writes trust through brew when wrapper mode is forced" do
      allow(Homebrew::EnvConfig).to receive(:force_brew_wrapper).and_return("/tmp/wrapper/brew")
      allow(Homebrew::Trust).to receive(:trust!).and_return(true)
      allow(described_class).to receive(:trusted?).with(:cask, "user/tap/foo").and_return(false, true)
      expect(Utils).to receive(:safe_popen_read)
        .with(HOMEBREW_BREW_FILE, "trust", "--cask", "user/tap/foo")
        .and_return("Trusted cask: user/tap/foo\n")

      expect(described_class.trust!(:cask, "user/tap/foo")).to be(true)
    end

    it "returns false when the entry is already trusted" do
      allow(Homebrew::EnvConfig).to receive(:force_brew_wrapper).and_return("/tmp/wrapper/brew")
      allow(Homebrew::Trust).to receive(:trust!).and_return(false)
      allow(described_class).to receive(:trusted?).with(:formula, "user/tap/foo").and_return(true)
      allow(Utils).to receive(:safe_popen_read)
        .with(HOMEBREW_BREW_FILE, "trust", "--formula", "user/tap/foo")
        .and_return("Already trusted formula: user/tap/foo\n")

      expect(described_class.trust!(:formula, "user/tap/foo")).to be(false)
    end
  end
end
