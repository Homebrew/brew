# frozen_string_literal: true

require "macos_version"

RSpec.describe MacOSVersion do
  let(:version) { described_class.new("10.14") }
  let(:big_sur_major) { described_class.new("11.0") }
  let(:big_sur_update) { described_class.new("11.1") }

  describe ".kernel_major_version" do
    it "returns the kernel major version" do
      expect(described_class.kernel_major_version(version)).to eq "18"
      expect(described_class.kernel_major_version(big_sur_major)).to eq "20"
      expect(described_class.kernel_major_version(big_sur_update)).to eq "20"
    end

    it "matches the major version returned by OS.kernel_version", :needs_macos do
      expect(described_class.kernel_major_version(OS::Mac.version)).to eq OS.kernel_version.major
    end
  end

  specify "comparison with Symbol" do
    expect(version).to be > :high_sierra
    expect(version).to eq :mojave
    # We're explicitly testing the `===` operator results here.
    expect(version).to be === :mojave # rubocop:disable Style/CaseEquality
    expect(version).to be < :catalina
  end

  specify "comparison with Integer" do
    expect(version).to be > 10
    expect(version).to be < 11
  end

  specify "comparison with String" do
    expect(version).to be > "10.3"
    expect(version).to eq "10.14"
    # We're explicitly testing the `===` operator results here.
    expect(version).to be === "10.14" # rubocop:disable Style/CaseEquality
    expect(version).to be < "10.15"
  end

  specify "comparison with Version" do
    expect(version).to be > Version.new("10.3")
    expect(version).to eq Version.new("10.14")
    # We're explicitly testing the `===` operator results here.
    expect(version).to be === Version.new("10.14") # rubocop:disable Style/CaseEquality
    expect(version).to be < Version.new("10.15")
  end

  describe "after Big Sur" do
    specify "comparison with :big_sur" do
      expect(big_sur_major).to eq :big_sur
      expect(big_sur_major).to be <= :big_sur
      expect(big_sur_major).to be >= :big_sur
      expect(big_sur_major).not_to be > :big_sur
      expect(big_sur_major).not_to be < :big_sur

      expect(big_sur_update).to eq :big_sur
      expect(big_sur_update).to be <= :big_sur
      expect(big_sur_update).to be >= :big_sur
      expect(big_sur_update).not_to be > :big_sur
      expect(big_sur_update).not_to be < :big_sur
    end
  end

  describe "#new" do
    it "raises an error if the version is not a valid macOS version" do
      expect do
        described_class.new("1.2")
      end.to raise_error(MacOSVersion::Error, 'unknown or unsupported macOS version: "1.2"')
    end

    it "creates a new version from a valid macOS version" do
      string_version = described_class.new("11")
      expect(string_version).to eq(:big_sur)
    end
  end

  describe "#from_symbol" do
    it "raises an error if the symbol is not a valid macOS version" do
      expect do
        described_class.from_symbol(:foo)
      end.to raise_error(MacOSVersion::Error, "unknown or unsupported macOS version: :foo")
    end

    it "creates a new version from a valid macOS version" do
      symbol_version = described_class.from_symbol(:mojave)
      expect(symbol_version).to eq(version)
    end
  end

  specify "#pretty_name" do
    expect(described_class.new("10.11").pretty_name).to eq("El Capitan")
    expect(described_class.new("10.14").pretty_name).to eq("Mojave")
  end

  specify "#inspect" do
    expect(described_class.new("11").inspect).to eq("#<MacOSVersion: \"11\">")
  end

  specify "#requires_nehalem_cpu?", :needs_macos do
    expect(Hardware::CPU).to receive(:type).at_least(:twice).and_return(:intel)
    expect(described_class.new("10.14").requires_nehalem_cpu?).to be true
    expect(described_class.new("10.12").requires_nehalem_cpu?).to be false
  end
end
