# frozen_string_literal: true

require "test/cask/dsl/shared_examples/base"

describe Cask::DSL::Caveats, :cask do
  subject(:caveats) { described_class.new(cask) }

  let(:cask) { Cask::CaskLoader.load(cask_path("basic-cask")) }
  let(:dsl) { caveats }

  it_behaves_like Cask::DSL::Base

  # TODO: add tests for Caveats DSL methods

  describe "#kext" do
    let(:cask) { instance_double(Cask::Cask) }

    it "points to System Preferences on macOS Monterey and earlier" do
      allow(MacOS).to receive(:version).and_return(MacOSVersion.new("12"))
      caveats.eval_caveats do
        kext
      end
      expect(caveats.to_s).to include("System Preferences → Security & Privacy → General")
    end

    it "points to System Settings on macOS Ventura and later" do
      allow(MacOS).to receive(:version).and_return(MacOSVersion.new("13"))
      caveats.eval_caveats do
        kext
      end
      expect(caveats.to_s).to include("System Settings → Privacy & Security")
    end
  end
end
