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

      it "installs package from URL remote" do
        allow(described_class).to receive(:`).with("flatpak remote-list --system --columns=name,url 2>/dev/null")
                                             .and_return("")
        expect(Homebrew::Bundle).to \
          receive(:system).with("flatpak", "remote-add", "--if-not-exists", "--system", "--no-gpg-verify",
                                "flathub-beta", "https://dl.flathub.org/beta-repo/", verbose: false)
                          .and_return(true)
        expect(Homebrew::Bundle).to \
          receive(:system).with("flatpak", "install", "-y", "--system", "flathub-beta", "org.godotengine.Godot",
                                verbose: false)
                          .and_return(true)
        expect(described_class.preinstall!("org.godotengine.Godot", remote: "https://dl.flathub.org/beta-repo/"))
          .to be(true)
        expect(described_class.install!("org.godotengine.Godot", remote: "https://dl.flathub.org/beta-repo/"))
          .to be(true)
      end

      it "handles remote URL conflicts by removing old remote and package" do
        # Package is NOT installed, but remote exists with different URL
        allow(described_class).to receive(:`).with("flatpak remote-list --system --columns=name,url 2>/dev/null")
                                             .and_return("flathub-beta\thttps://old.url/repo/\n")

        # Package is not installed initially
        allow(described_class).to receive(:installed_packages)
          .and_return([])

        # Should remove old remote (no package to uninstall since it's not installed)
        expect(Homebrew::Bundle).to \
          receive(:system).with("flatpak", "remote-delete", "--system", "flathub-beta", verbose: false)
                          .and_return(true)

        # Should add new remote
        expect(Homebrew::Bundle).to \
          receive(:system).with("flatpak", "remote-add", "--if-not-exists", "--system", "--no-gpg-verify",
                                "flathub-beta", "https://dl.flathub.org/beta-repo/", verbose: false)
                          .and_return(true)

        # Should install package from new remote
        expect(Homebrew::Bundle).to \
          receive(:system).with("flatpak", "install", "-y", "--system", "flathub-beta", "org.godotengine.Godot",
                                verbose: false)
                          .and_return(true)

        expect(described_class.preinstall!("org.godotengine.Godot", remote: "https://dl.flathub.org/beta-repo/"))
          .to be(true)
        expect(described_class.install!("org.godotengine.Godot", remote: "https://dl.flathub.org/beta-repo/"))
          .to be(true)
      end
    end
  end

  describe ".generate_remote_name" do
    it "generates simple name from beta repo URL" do
      expect(described_class.generate_remote_name("https://dl.flathub.org/beta-repo/"))
        .to eq("flathub-beta")
    end

    it "generates simple name from standard flathub URL" do
      expect(described_class.generate_remote_name("https://dl.flathub.org/repo/"))
        .to eq("flathub")
    end

    it "generates name from custom domain" do
      expect(described_class.generate_remote_name("https://custom.example.com/flatpak-repo/"))
        .to eq("custom")
    end

    it "handles URLs without path hints" do
      expect(described_class.generate_remote_name("https://example.com/"))
        .to eq("example")
    end
  end
end
