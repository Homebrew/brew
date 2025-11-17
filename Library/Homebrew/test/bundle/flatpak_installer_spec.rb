# frozen_string_literal: true

require "bundle"
require "bundle/flatpak_installer"

RSpec.describe Homebrew::Bundle::FlatpakInstaller do
  context "when Flatpak is not installed", :needs_linux do
    before do
      described_class.reset!
      allow(Homebrew::Bundle).to receive(:flatpak_installed?).and_return(false)
    end

    it "tries to install flatpak" do
      expect(Homebrew::Bundle).to \
        receive(:system).with(HOMEBREW_BREW_FILE, "install", "--formula", "flatpak", verbose: false)
                        .and_return(true)
      expect { described_class.preinstall!("org.gnome.Calculator") }.to raise_error(RuntimeError)
    end
  end

  context "when Flatpak is installed", :needs_linux do
    before do
      allow(Homebrew::Bundle).to receive(:flatpak_installed?).and_return(true)
    end

    context "when package is installed" do
      before do
        allow(described_class).to receive(:installed_packages)
          .and_return([{ name: "org.gnome.Calculator", remote: "flathub" }])
      end

      it "skips" do
        expect(Homebrew::Bundle).not_to receive(:system)
        expect(described_class.preinstall!("org.gnome.Calculator")).to be(false)
      end
    end

    context "when package is not installed" do
      before do
        allow(Homebrew::Bundle).to receive(:which_flatpak).and_return(Pathname.new("flatpak"))
        allow(described_class).to receive(:installed_packages).and_return([])
      end

      it "installs package" do
        expect(Homebrew::Bundle).to \
          receive(:system).with("flatpak", "install", "-y", "--system", "flathub", "org.gnome.Calculator",
                                verbose: false)
                          .and_return(true)
        expect(described_class.preinstall!("org.gnome.Calculator")).to be(true)
        expect(described_class.install!("org.gnome.Calculator")).to be(true)
      end
    end
  end
end
