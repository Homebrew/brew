# frozen_string_literal: true

require "bump_version_parser"

describe Homebrew::BumpVersionParser do
  let(:general_version) { "1.2.3" }
  let(:intel_version) { "2.3.4" }
  let(:arm_version) { "3.4.5" }

  context "when initializing with no versions" do
    it "raises a usage error" do
      expect do
        described_class.new
      end.to raise_error(UsageError, "Invalid usage: `--version` must not be empty.")
    end
  end

  context "when initializing with valid versions" do
    let(:new_version) { described_class.new(general: general_version, arm: arm_version, intel: intel_version) }

    it "correctly parses general version" do
      expect(new_version.general).to eq(Cask::DSL::Version.new(general_version.to_s))
    end

    it "correctly parses arm version" do
      expect(new_version.arm).to eq(Cask::DSL::Version.new(arm_version.to_s))
    end

    it "correctly parses intel version" do
      expect(new_version.intel).to eq(Cask::DSL::Version.new(intel_version.to_s))
    end

    context "when only the intel version is provided" do
      it "raises a UsageError" do
        expect do
          described_class.new(intel: intel_version)
        end.to raise_error(UsageError,
                           "Invalid usage: `--version-arm` must not be empty.")
      end
    end

    context "when only the arm version is provided" do
      it "raises a UsageError" do
        expect do
          described_class.new(arm: arm_version)
        end.to raise_error(UsageError,
                           "Invalid usage: `--version-intel` must not be empty.")
      end
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
end
