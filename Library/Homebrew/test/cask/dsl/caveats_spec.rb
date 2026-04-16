# typed: false
# frozen_string_literal: true

require "test/cask/dsl/shared_examples/base"

RSpec.describe Cask::DSL::Caveats, :cask do
  subject(:caveats) { described_class.new(cask) }

  let(:cask) { Cask::CaskLoader.load(cask_path("basic-cask")) }
  let(:dsl) { caveats }

  it_behaves_like Cask::DSL::Base

  describe "#to_s_without_conditional" do
    let(:cask) { instance_double(Cask::Cask, token: "test-cask") }

    it "excludes requires_rosetta caveat text" do
      allow(Homebrew::SimulateSystem).to receive(:current_arch).and_return(:arm)
      caveats.eval_caveats do
        requires_rosetta
      end

      expect(caveats.to_s).to include("requires Rosetta 2")
      expect(caveats.to_s_without_conditional).not_to include("requires Rosetta 2")
    end

    it "keeps non-conditional built-in caveats" do
      caveats.eval_caveats do
        reboot
      end

      expect(caveats.to_s_without_conditional).to include("must reboot")
    end

    it "keeps custom caveats" do
      caveats.eval_caveats { "Custom caveat text\n" }

      expect(caveats.to_s_without_conditional).to include("Custom caveat text")
    end
  end

  describe "#invoked?" do
    let(:cask) { instance_double(Cask::Cask, token: "test-cask") }

    it "returns true for invoked caveats" do
      allow(Homebrew::SimulateSystem).to receive(:current_arch).and_return(:arm)
      caveats.eval_caveats do
        requires_rosetta
      end

      expect(caveats.invoked?(:requires_rosetta)).to be true
    end

    it "returns true even when caveat condition is false" do
      allow(Homebrew::SimulateSystem).to receive(:current_arch).and_return(:intel)
      caveats.eval_caveats do
        requires_rosetta
      end

      expect(caveats.invoked?(:requires_rosetta)).to be true
      expect(caveats.to_s).to be_empty
    end

    it "returns false for non-invoked caveats" do
      expect(caveats.invoked?(:requires_rosetta)).to be false
    end
  end

  describe "#kext" do
    let(:cask) { instance_double(Cask::Cask) }

    it "returns System Settings on macOS Ventura or later" do
      allow(MacOS).to receive(:version).and_return(MacOSVersion.from_symbol(:ventura))
      caveats.eval_caveats do
        kext
      end
      expect(caveats.to_s).to be_empty
    end

    it "returns System Preferences on macOS Sonoma and earlier" do
      allow(MacOS).to receive(:version).and_return(MacOSVersion.from_symbol(:sonoma))
      caveats.eval_caveats do
        kext
      end
      expect(caveats.to_s).to include("System Settings → Privacy & Security")
    end
  end
end
