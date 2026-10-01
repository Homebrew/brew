# typed: true
# frozen_string_literal: true

require "macos_version"

RSpec.describe MacOSVersion do
  let(:version) { described_class.new("11") }
  let(:tahoe_major) { described_class.new("26.0") }
  let(:big_sur_major) { described_class.new("11.0") }
  let(:big_sur_update) { described_class.new("11.1") }
  let(:frozen_version) { described_class.new("11").freeze }

  describe "::kernel_major_version" do
    it "returns the kernel major version" do
      expect(described_class.kernel_major_version(version)).to eq "20"
      expect(described_class.kernel_major_version(tahoe_major)).to eq "25"
      expect(described_class.kernel_major_version(big_sur_major)).to eq "20"
      expect(described_class.kernel_major_version(big_sur_update)).to eq "20"
    end

    it "matches the major version returned by OS.kernel_version", :needs_macos do
      ENV["HOMEBREW_FAKE_MACOS"] = nil
      expect(described_class.kernel_major_version(OS::Mac.version)).to eq OS.kernel_version.major
    end
  end

  describe "::from_symbol" do
    it "raises an error if the symbol is not a valid macOS version" do
      expect do
        described_class.from_symbol(:foo)
      end.to raise_error(MacOSVersion::Error, "unknown or unsupported macOS version: :foo")
    end

    it "raises an error if the macOS release is retired" do
      expect do
        described_class.from_symbol(:catalina)
      end.to raise_error(MacOSVersion::Error, "unknown or unsupported macOS version: :catalina")
    end

    it "creates a new version from a valid macOS version" do
      symbol_version = described_class.from_symbol(:big_sur)
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

  specify "comparisons" do
    expect(version).to be >= :big_sur
    expect(version).to eq :big_sur
    # We're explicitly testing the `===` operator results here.
    expect(version).to be === :big_sur # rubocop:disable Style/CaseEquality
    expect(version).to be < :tahoe

    # This should work like a normal comparison but the result won't be added
    # to the `@comparison_cache` hash because the object is frozen.
    expect(frozen_version).to eq :big_sur
    expect(frozen_version.comparison_cache).to eq({})

    expect(version).to be > 10
    expect(version).to be < 12
    expect(version).to be > "10"
    expect(version).to eq "11"
    # We're explicitly testing the `===` operator results here.
    expect(version).to be === "11" # rubocop:disable Style/CaseEquality
    expect(version).to be < "12"
    expect(version).to be > Version.new("10")
    expect(version).to eq Version.new("11")
    # We're explicitly testing the `===` operator results here.
    expect(version).to be === Version.new("11") # rubocop:disable Style/CaseEquality
    expect(version).to be < Version.new("12")
    expect(described_class.new("11").inspect).to eq("#<MacOSVersion: \"11\">")
    expect(described_class.new(MacOSVersion::SYMBOLS.values.first).outdated_release?).to be false
    expect(described_class.new("13").outdated_release?).to be true
    expect(described_class.new("1000").prerelease?).to be true
    expect(described_class.new("13").unsupported_release?).to be true
    expect(described_class.new("1000").unsupported_release?).to be true
  end

  describe "release support" do
    it "supports Sequoia, Tahoe and Golden Gate" do
      expect(%w[15 26 27].map { |release| described_class.new(release).unsupported_release? }).to all(be false)
    end

    context "when running Sonoma" do
      it "classifies the release as outdated" do
        expect(described_class.new("14").outdated_release?).to be true
      end
    end

    context "when running macOS 28" do
      it "classifies the release as a prerelease" do
        expect(described_class.new("28").prerelease?).to be true
      end
    end
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
    context "when the release is before Big Sur" do
      it "preserves the minor version" do
        expect(described_class.new("10.15.7").strip_patch).to eq(described_class.new("10.15"))
      end
    end

    context "when the release is Big Sur or newer" do
      it "returns the major version" do
        expect(big_sur_update.strip_patch).to eq(described_class.new("11"))
      end
    end

    context "when the version is null" do
      it "returns itself" do
        expect(MacOSVersion::NULL.strip_patch).to be MacOSVersion::NULL
      end
    end
  end

  describe "#release_name" do
    context "when the release is known" do
      it "returns the name of a retired release" do
        expect(described_class.new("10.15.7").release_name).to eq("Catalina")
      end
    end

    context "when the release is unknown" do
      it "returns nil" do
        expect(described_class.new("10.10").release_name).to be_nil
      end
    end
  end

  describe "#release_version" do
    context "when the release has a compatibility version" do
      it "returns the canonical release version" do
        expect(described_class.new("10.16.0").release_version).to eq("11")
      end
    end

    context "when the release has no compatibility version" do
      it "returns the version without the patch" do
        expect(described_class.new("10.15.7").release_version).to eq("10.15")
      end
    end
  end

  describe "#to_sym with a retired release" do
    it "returns dunno" do
      expect(described_class.new("10.15").to_sym).to eq(:dunno)
    end
  end

  describe "#to_sym with a compatibility version" do
    it "returns dunno" do
      expect(described_class.new("10.16").to_sym).to eq(:dunno)
    end
  end

  specify "#to_sym" do
    version_symbol = :big_sur

    # We call this more than once to exercise the caching logic
    expect(version.to_sym).to eq(version_symbol)
    expect(version.to_sym).to eq(version_symbol)

    # This should work like a normal but the symbol won't be stored as the
    # `@sym` instance variable because the object is frozen.
    expect(frozen_version.to_sym).to eq(version_symbol)
    expect(frozen_version.sym).to be_nil

    expect(MacOSVersion::NULL.to_sym).to eq(:dunno)
  end

  specify "#pretty_name" do
    version_pretty_name = "Big Sur"

    expect(described_class.new("11").pretty_name).to eq("Big Sur")

    # We call this more than once to exercise the caching logic
    expect(version.pretty_name).to eq(version_pretty_name)
    expect(version.pretty_name).to eq(version_pretty_name)

    # This should work like a normal but the computed name won't be stored as
    # the `@pretty_name` instance variable because the object is frozen.
    expect(frozen_version.pretty_name).to eq(version_pretty_name)
    # Read the raw ivar: a reader would collide with the memoising `pretty_name`.
    # rubocop:disable Homebrew/NoInstanceVariableAccessInTests
    expect(frozen_version.instance_variable_get(:@pretty_name)).to be_nil
    # rubocop:enable Homebrew/NoInstanceVariableAccessInTests
  end

  describe "#pretty_name with a retired release" do
    it "returns the release name" do
      expect(described_class.new("10.15").pretty_name).to eq("Catalina")
    end
  end

  describe "#requires_nehalem_cpu?", :needs_macos do
    context "when CPU is Intel" do
      it "returns true if version requires a Nehalem CPU" do
        allow(Hardware::CPU).to receive(:type).and_return(:intel)
        expect(described_class.new("11").requires_nehalem_cpu?).to be true
      end
    end

    context "when CPU is not Intel" do
      it "raises an error" do
        allow(Hardware::CPU).to receive(:type).and_return(:arm)
        expect { described_class.new("11").requires_nehalem_cpu? }
          .to raise_error(ArgumentError)
      end
    end

    it "returns false when version is null" do
      expect(MacOSVersion::NULL.requires_nehalem_cpu?).to be false
    end
  end
end
