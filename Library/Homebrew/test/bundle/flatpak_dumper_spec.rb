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

    it "returns an empty list" do
      expect(dumper.packages).to be_empty
    end

    it "dumps an empty string" do
      expect(dumper.dump).to eql("")
    end
  end

  context "when flatpak is installed" do
    before do
      described_class.reset!
      allow(OS).to receive(:mac?).and_return(false)
      allow(Homebrew::Bundle).to receive_messages(flatpak_installed?: true,
                                                  which_flatpak:      Pathname.new("flatpak"))
    end

    it "returns package list with remotes" do
      allow(described_class).to receive(:`).with("flatpak list --app --columns=application,origin 2>/dev/null")
                                           .and_return("org.gnome.Calculator\tflathub\ncom.spotify.Client\tflathub\n")
      expect(dumper.packages_with_remotes).to eql([
        { name: "com.spotify.Client", remote: "flathub" },
        { name: "org.gnome.Calculator", remote: "flathub" },
      ])
    end

    it "returns package names only" do
      allow(described_class).to receive(:`).with("flatpak list --app --columns=application,origin 2>/dev/null")
                                           .and_return("org.gnome.Calculator\tflathub\ncom.spotify.Client\tflathub\n")
      expect(dumper.packages).to eql(["com.spotify.Client", "org.gnome.Calculator"])
    end

    it "dumps package list without remote for flathub packages" do
      allow(dumper).to receive(:packages_with_remotes).and_return([
        { name: "org.gnome.Calculator", remote: "flathub" },
        { name: "com.spotify.Client", remote: "flathub" },
      ])
      expect(dumper.dump).to eql("flatpak \"org.gnome.Calculator\"\nflatpak \"com.spotify.Client\"")
    end

    it "dumps package list with remote for non-flathub packages" do
      allow(dumper).to receive(:packages_with_remotes).and_return([
        { name: "org.gnome.Calculator", remote: "flathub" },
        { name: "com.custom.App", remote: "custom-repo" },
      ])
      expect(dumper.dump).to eql(
        "flatpak \"org.gnome.Calculator\"\nflatpak \"com.custom.App\", remote: \"custom-repo\"",
      )
    end

    it "handles packages without origin" do
      allow(described_class).to receive(:`).with("flatpak list --app --columns=application,origin 2>/dev/null")
                                           .and_return("org.gnome.Calculator\n")
      expect(dumper.packages_with_remotes).to eql([
        { name: "org.gnome.Calculator", remote: "flathub" },
      ])
    end
  end
end
