# frozen_string_literal: true

require "bundle"
require "bundle/flatpak_remote_installer"
require "bundle/flatpak_remote_dumper"

RSpec.describe Homebrew::Bundle::FlatpakRemoteInstaller, :needs_linux do
  describe ".installed_remotes" do
    before do
      Homebrew::Bundle::FlatpakRemoteDumper.reset!
    end

    it "calls flatpak" do
      allow(Homebrew::Bundle).to receive(:flatpak_installed?).and_return(true)
      expect { described_class.installed_remotes }.not_to raise_error
    end
  end

  context "when remote is installed" do
    before do
      allow(described_class).to receive(:installed_remotes).and_return(["flathub"])
      allow(Homebrew::Bundle).to receive(:flatpak_installed?).and_return(true)
    end

    it "skips" do
      expect(Homebrew::Bundle).not_to receive(:system)
      expect(described_class.preinstall!("flathub")).to be(false)
    end
  end

  context "when remote is not installed" do
    before do
      allow(described_class).to receive(:installed_remotes).and_return([])
      allow(Homebrew::Bundle).to receive_messages(flatpak_installed?: true,
                                                  which_flatpak:      Pathname.new("/usr/bin/flatpak"))
    end

    it "adds remote" do
      expect(Homebrew::Bundle).to receive(:system).with(
        "/usr/bin/flatpak",
        "remote-add",
        "--if-not-exists",
        "--system",
        "flathub",
        "https://flathub.org/repo/flathub.flatpakrepo",
        verbose: false,
      ).and_return(true)
      expect(described_class.preinstall!("flathub", url: "https://flathub.org/repo/flathub.flatpakrepo")).to be(true)
      expect(described_class.install!("flathub", url: "https://flathub.org/repo/flathub.flatpakrepo")).to be(true)
    end

    it "requires URL" do
      expect(described_class.preinstall!("custom-remote")).to be(true)
      expect(described_class.install!("custom-remote")).to be(false)
    end

    it "fails when system command fails" do
      expect(Homebrew::Bundle).to receive(:system).and_return(false)
      expect(described_class.preinstall!("flathub", url: "https://example.com/repo")).to be(true)
      expect(described_class.install!("flathub", url: "https://example.com/repo")).to be(false)
    end
  end
end
