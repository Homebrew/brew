# frozen_string_literal: true

require "bundle"
require "bundle/tap_installer"
require "bundle/tap_dumper"

RSpec.describe Homebrew::Bundle::TapInstaller do
  describe ".installed_taps" do
    before do
      Homebrew::Bundle::TapDumper.reset!
    end

    it "calls Homebrew" do
      expect { described_class.installed_taps }.not_to raise_error
    end
  end

  context "when tap is installed" do
    before do
      allow(described_class).to receive(:installed_taps).and_return(["homebrew/cask"])
    end

    it "skips" do
      expect(Homebrew::Bundle).not_to receive(:system)
      expect(described_class.preinstall!("homebrew/cask")).to be(false)
    end
  end

  context "when tap is not installed" do
    before do
      allow(described_class).to receive(:installed_taps).and_return([])
    end

    it "taps" do
      expect(Homebrew::Bundle).to receive(:system).with(HOMEBREW_BREW_FILE, "tap", "homebrew/cask",
                                                        verbose: false).and_return(true)
      expect(described_class.preinstall!("homebrew/cask")).to be(true)
      expect(described_class.install!("homebrew/cask")).to be(true)
    end

    context "with clone target" do
      it "taps" do
        expect(Homebrew::Bundle).to \
          receive(:system).with(HOMEBREW_BREW_FILE, "tap", "homebrew/cask", "clone_target_path",
                                verbose: false).and_return(true)
        expect(described_class.preinstall!("homebrew/cask", clone_target: "clone_target_path")).to be(true)
        expect(described_class.install!("homebrew/cask", clone_target: "clone_target_path")).to be(true)
      end

      it "fails" do
        expect(Homebrew::Bundle).to \
          receive(:system).with(HOMEBREW_BREW_FILE, "tap", "homebrew/cask", "clone_target_path",
                                verbose: false).and_return(false)
        expect(described_class.preinstall!("homebrew/cask", clone_target: "clone_target_path")).to be(true)
        expect(described_class.install!("homebrew/cask", clone_target: "clone_target_path")).to be(false)
      end
    end
  end
end
