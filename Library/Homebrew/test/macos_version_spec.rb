# frozen_string_literal: true

require "macos_version"

RSpec.describe MacOSVersion do
  let(:version) { described_class.new("10.14") }
  let(:tahoe_major) { described_class.new("26.0") }
  let(:big_sur_major) { described_class.new("11.0") }
  let(:big_sur_update) { described_class.new("11.1") }
  let(:frozen_version) { described_class.new("10.14").freeze }

  describe "::kernel_major_version" do
    it "returns the kernel major version" do
      expect(described_class.kernel_major_version(version)).to eq "18"
      expect(described_class.kernel_major_version(tahoe_major)).to eq "25"
      expect(described_class.kernel_major_version(big_sur_major)).to eq "20"
      expect(described_class.kernel_major_version(big_sur_update)).to eq "20"
    end

    it "matches the major version returned by OS.kernel_version", :needs_macos do
      expect(described_class.kernel_major_version(OS::Mac.version)).to eq OS.kernel_version.major
    end
  end

  describe "::from_symbol" do
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

  specify "comparison with Symbol" do
    expect(version).to be > :high_sierra
    expect(version).to eq :mojave
    # We're explicitly testing the `===` operator results here.
    expect(version).to be === :mojave # rubocop:disable Style/CaseEquality
    expect(version).to be < :catalina

    # This should work like a normal comparison but the result won't be added
    # to the `@comparison_cache` hash because the object is frozen.
    expect(frozen_version).to eq :mojave
    expect(frozen_version.instance_variable_get(:@comparison_cache)).to eq({})
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

  describe "#strip_patch" do
    let(:catalina_update) { described_class.new("10.15.1") }

    it "returns the version without the patch" do
      expect(big_sur_update.strip_patch).to eq(described_class.new("11"))
      expect(catalina_update.strip_patch).to eq(described_class.new("10.15"))
    end

    it "returns self if version is null" do
      expect(described_class::NULL.strip_patch).to be described_class::NULL
    end
  end

  specify "#to_sym" do
    version_symbol = :mojave

    # We call this more than once to exercise the caching logic
    expect(version.to_sym).to eq(version_symbol)
    expect(version.to_sym).to eq(version_symbol)

    # This should work like a normal but the symbol won't be stored as the
    # `@sym` instance variable because the object is frozen.
    expect(frozen_version.to_sym).to eq(version_symbol)
    expect(frozen_version.instance_variable_get(:@sym)).to be_nil

    expect(described_class::NULL.to_sym).to eq(:dunno)
  end

  specify "#pretty_name" do
    version_pretty_name = "Mojave"

    expect(described_class.new("10.11").pretty_name).to eq("El Capitan")

    # We call this more than once to exercise the caching logic
    expect(version.pretty_name).to eq(version_pretty_name)
    expect(version.pretty_name).to eq(version_pretty_name)

    # This should work like a normal but the computed name won't be stored as
    # the `@pretty_name` instance variable because the object is frozen.
    expect(frozen_version.pretty_name).to eq(version_pretty_name)
    expect(frozen_version.instance_variable_get(:@pretty_name)).to be_nil
  end

  specify "#inspect" do
    expect(described_class.new("11").inspect).to eq("#<MacOSVersion: \"11\">")
  end

  specify "#outdated_release?" do
    expect(described_class.new(described_class::SYMBOLS.values.first).outdated_release?).to be false
    expect(described_class.new("10.0").outdated_release?).to be true
  end

  specify "#prerelease?" do
    expect(described_class.new("1000").prerelease?).to be true
  end

  specify "#unsupported_release?" do
    expect(described_class.new("10.0").unsupported_release?).to be true
    expect(described_class.new("1000").prerelease?).to be true
  end

  describe "#requires_nehalem_cpu?", :needs_macos do
    context "when CPU is Intel" do
      it "returns true if version requires a Nehalem CPU" do
        allow(Hardware::CPU).to receive(:type).and_return(:intel)
        expect(described_class.new("10.14").requires_nehalem_cpu?).to be true
      end

      it "returns false if version does not require a Nehalem CPU" do
        allow(Hardware::CPU).to receive(:type).and_return(:intel)
        expect(described_class.new("10.12").requires_nehalem_cpu?).to be false
      end
    end

    context "when CPU is not Intel" do
      it "raises an error" do
        allow(Hardware::CPU).to receive(:type).and_return(:arm)
        expect { described_class.new("10.14").requires_nehalem_cpu? }
          .to raise_error(ArgumentError)
      end
    end

    it "returns false when version is null" do
      expect(described_class::NULL.requires_nehalem_cpu?).to be false
    end
  end
end
