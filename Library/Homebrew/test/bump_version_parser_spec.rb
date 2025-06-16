# frozen_string_literal: true

require "bump_version_parser"

RSpec.describe Homebrew::BumpVersionParser do
  let(:general_version) { "1.2.3" }
  let(:intel_version) { "2.3.4" }
  let(:arm_version) { "3.4.5" }

  context "when initializing with no versions" do
    it "raises a usage error" do
      expect do
        described_class.new
      end.to raise_error(UsageError,
                         "Invalid usage: `--version` must not be empty.")
    end
  end

  context "when initializing with only an intel version" do
    it "raises a UsageError" do
      expect do
        described_class.new(intel: intel_version)
      end.to raise_error(UsageError,
                         "Invalid usage: `--version-arm` must not be empty.")
    end
  end

  context "when initializing with only an arm version" do
    it "raises a UsageError" do
      expect do
        described_class.new(arm: arm_version)
      end.to raise_error(UsageError,
                         "Invalid usage: `--version-intel` must not be empty.")
    end
  end

  context "when initializing with arm and intel versions" do
    let(:new_version_arm_intel) { described_class.new(arm: arm_version, intel: intel_version) }

    it "correctly parses arm and intel versions" do
      expect(new_version_arm_intel.arm).to eq(Cask::DSL::Version.new(arm_version.to_s))
      expect(new_version_arm_intel.intel).to eq(Cask::DSL::Version.new(intel_version.to_s))
    end
  end

  context "when initializing with all versions" do
    let(:new_version) { described_class.new(general: general_version, arm: arm_version, intel: intel_version) }
    let(:new_version_version) do
      described_class.new(
        general: Version.new(general_version),
        arm:     Version.new(arm_version),
        intel:   Version.new(intel_version),
      )
    end

    it "correctly parses general version" do
      expect(new_version.general).to eq(Cask::DSL::Version.new(general_version.to_s))
      expect(new_version_version.general).to eq(Cask::DSL::Version.new(general_version.to_s))
    end

    it "correctly parses arm version" do
      expect(new_version.arm).to eq(Cask::DSL::Version.new(arm_version.to_s))
      expect(new_version_version.arm).to eq(Cask::DSL::Version.new(arm_version.to_s))
    end

    it "correctly parses intel version" do
      expect(new_version.intel).to eq(Cask::DSL::Version.new(intel_version.to_s))
      expect(new_version_version.intel).to eq(Cask::DSL::Version.new(intel_version.to_s))
    end

    context "when the version is latest" do
      it "returns a version object for latest" do
        new_version = described_class.new(general: "latest")
        expect(new_version.general.to_s).to eq("latest")
      end

      context "when the version is not latest" do
        it "returns a version object for the given version" do
          new_version = described_class.new(general: general_version)
          expect(new_version.general.to_s).to eq(general_version)
        end
      end
    end

    context "when checking if VersionParser is blank" do
      it "returns false if any version is present" do
        new_version = described_class.new(general: general_version.to_s, arm: "", intel: "")
        expect(new_version.blank?).to be(false)
      end
    end
  end

  describe "#==" do
    let(:new_version) { described_class.new(general: general_version, arm: arm_version, intel: intel_version) }

    context "when other object is not a `BumpVersionParser`" do
      it "returns false" do
        expect(new_version == Version.new("1.2.3")).to be(false)
      end
    end

    context "when comparing objects with equal versions" do
      it "returns true" do
        same_version = described_class.new(general: general_version, arm: arm_version, intel: intel_version)
        expect(new_version == same_version).to be(true)
      end
    end

    context "when comparing objects with different versions" do
      it "returns false" do
        different_general_version = described_class.new(general: "3.2.1", arm: arm_version, intel: intel_version)
        different_arm_version = described_class.new(general: general_version, arm: "4.3.2", intel: intel_version)
        different_intel_version = described_class.new(general: general_version, arm: arm_version, intel: "5.4.3")
        different_general_arm_versions = described_class.new(general: "3.2.1", arm: "4.3.2", intel: intel_version)
        different_arm_intel_versions = described_class.new(general: general_version, arm: "4.3.2", intel: "5.4.3")
        different_general_intel_versions = described_class.new(general: "3.2.1", arm: arm_version, intel: "5.4.3")

        expect(new_version == different_general_version).to be(false)
        expect(new_version == different_arm_version).to be(false)
        expect(new_version == different_intel_version).to be(false)
        expect(new_version == different_general_arm_versions).to be(false)
        expect(new_version == different_arm_intel_versions).to be(false)
        expect(new_version == different_general_intel_versions).to be(false)
      end
    end
  end
end
