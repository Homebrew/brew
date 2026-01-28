# frozen_string_literal: true

require "test/cask/dsl/shared_examples/base"

RSpec.describe Cask::DSL::Caveats, :cask do
  subject(:caveats) { described_class.new(cask) }

  let(:cask) { Cask::CaskLoader.load(cask_path("basic-cask")) }
  let(:dsl) { caveats }

  it_behaves_like Cask::DSL::Base

  # TODO: add tests for Caveats DSL methods

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
