# frozen_string_literal: true

require "bundle"
require "bundle/flatpak_dumper"

RSpec.describe Homebrew::Bundle::FlatpakDumper do
  subject(:dumper) { described_class }

  context "when flatpak is not installed" do
    before do
      described_class.reset!
      allow(Homebrew::Bundle).to receive(:flatpak_installed?).and_return(false)
    end

    it "returns an empty list and dumps an empty string" do
      expect(dumper.packages).to be_empty
      expect(dumper.dump).to eql("")
    end
  end

  context "when flatpak is installed", :needs_linux do
    before do
      described_class.reset!
      allow(Homebrew::Bundle).to receive_messages(flatpak_installed?: true,
                                                  which_flatpak:      Pathname.new("flatpak"))
    end

    it "returns remote URLs" do
      allow(described_class).to receive(:`).with("flatpak remote-list --system --columns=name,url 2>/dev/null")
                                           .and_return("flathub\thttps://dl.flathub.org/repo/\nfedora\thttps://registry.fedoraproject.org/\n")
      expect(dumper.remote_urls).to eql({
        "flathub" => "https://dl.flathub.org/repo/",
        "fedora"  => "https://registry.fedoraproject.org/",
      })
    end

    it "returns package list with remotes and URLs" do
      allow(described_class).to receive(:`).with("flatpak list --app --columns=application,origin 2>/dev/null")
                                           .and_return("org.gnome.Calculator\tflathub\ncom.spotify.Client\tflathub\n")
      allow(described_class).to receive(:`).with("flatpak remote-list --system --columns=name,url 2>/dev/null")
                                           .and_return("flathub\thttps://dl.flathub.org/repo/\n")
      expect(dumper.packages_with_remotes).to eql([
        { name: "com.spotify.Client", remote: "flathub", remote_url: "https://dl.flathub.org/repo/" },
        { name: "org.gnome.Calculator", remote: "flathub", remote_url: "https://dl.flathub.org/repo/" },
      ])
    end

    it "returns package names only" do
      allow(described_class).to receive(:`).with("flatpak list --app --columns=application,origin 2>/dev/null")
                                           .and_return("org.gnome.Calculator\tflathub\ncom.spotify.Client\tflathub\n")
      allow(described_class).to receive(:`).with("flatpak remote-list --system --columns=name,url 2>/dev/null")
                                           .and_return("flathub\thttps://dl.flathub.org/repo/\n")
      expect(dumper.packages).to eql(["com.spotify.Client", "org.gnome.Calculator"])
    end

    it "dumps package list without remote for flathub packages" do
      allow(dumper).to receive(:packages_with_remotes).and_return([
        { name: "org.gnome.Calculator", remote: "flathub" },
        { name: "com.spotify.Client", remote: "flathub" },
      ])
      expect(dumper.dump).to eql("flatpak \"org.gnome.Calculator\"\nflatpak \"com.spotify.Client\"")
    end

    it "dumps package list with remote URL for non-flathub packages" do
      allow(dumper).to receive(:packages_with_remotes).and_return([
        { name: "org.gnome.Calculator", remote: "flathub", remote_url: "https://dl.flathub.org/repo/" },
        { name: "org.godotengine.Godot", remote: "godot-beta", remote_url: "https://dl.flathub.org/beta-repo/" },
      ])
      expect(dumper.dump).to eql(
        "flatpak \"org.gnome.Calculator\"\nflatpak \"org.godotengine.Godot\", remote: \"https://dl.flathub.org/beta-repo/\"",
      )
    end

    it "dumps package with remote name when URL is not available" do
      allow(dumper).to receive(:packages_with_remotes).and_return([
        { name: "com.custom.App", remote: "custom-repo", remote_url: nil },
      ])
      expect(dumper.dump).to eql(
        "flatpak \"com.custom.App\", remote: \"custom-repo\"",
      )
    end

    it "handles packages without origin" do
      allow(described_class).to receive(:`).with("flatpak list --app --columns=application,origin 2>/dev/null")
                                           .and_return("org.gnome.Calculator\n")
      allow(described_class).to receive(:`).with("flatpak remote-list --system --columns=name,url 2>/dev/null")
                                           .and_return("flathub\thttps://dl.flathub.org/repo/\n")
      expect(dumper.packages_with_remotes).to eql([
        { name: "org.gnome.Calculator", remote: "flathub", remote_url: "https://dl.flathub.org/repo/" },
      ])
    end
  end
end
