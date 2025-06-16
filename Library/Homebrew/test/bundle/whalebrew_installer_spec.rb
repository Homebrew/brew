# frozen_string_literal: true

require "bundle"
require "bundle/whalebrew_installer"
require "bundle/whalebrew_dumper"

RSpec.describe Homebrew::Bundle::WhalebrewInstaller do
  before do
    stub_formula_loader formula("whalebrew") { url "whalebrew-1.0" }
  end

  describe ".installed_images" do
    before do
      described_class.reset!
      Homebrew::Bundle::WhalebrewDumper.reset!
    end

    it "shells out" do
      expect { described_class.installed_images }.not_to raise_error
    end
  end

  describe ".image_installed?" do
    context "when an image is already installed" do
      before do
        described_class.reset!
      end

      it "returns true" do
        allow(Homebrew::Bundle::WhalebrewDumper).to receive(:images).and_return(["whalebrew/wget"])
        expect(described_class.image_installed?("whalebrew/wget")).to be(true)
      end
    end
  end

  context "when whalebrew isn't installed" do
    before do
      allow(Homebrew::Bundle).to receive(:whalebrew_installed?).and_return(false)
    end

    it "successfully installs whalebrew" do
      expect(Homebrew::Bundle).to receive(:system).with(HOMEBREW_BREW_FILE, "install", "--formula", "whalebrew",
                                                        verbose: false)
                                                  .and_return(true)
      expect { described_class.preinstall("whalebrew/wget") }.to raise_error(RuntimeError)
    end
  end

  context "when whalebrew is installed" do
    before do
      described_class.reset!
      Homebrew::Bundle::WhalebrewDumper.reset!
      allow(Homebrew::Bundle).to receive(:whalebrew_installed?).and_return(true)
      allow(Homebrew::Bundle).to receive(:system).with("whalebrew", "install", "whalebrew/wget", verbose: false)
                                                 .and_return(true)
    end

    context "when the requested image is already installed" do
      before do
        allow(described_class).to receive(:image_installed?).with("whalebrew/wget").and_return(true)
      end

      it "skips" do
        expect(described_class.preinstall("whalebrew/wget")).to be(false)
      end
    end
  end
end
