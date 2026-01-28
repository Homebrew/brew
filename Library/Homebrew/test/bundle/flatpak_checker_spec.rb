# frozen_string_literal: true

require "bundle"
require "bundle/flatpak_checker"
require "bundle/flatpak_installer"

RSpec.describe Homebrew::Bundle::Checker::FlatpakChecker do
  subject(:checker) { described_class.new }

  let(:entry) { Homebrew::Bundle::Dsl::Entry.new(:flatpak, "org.gnome.Calculator") }

  before do
    allow(Homebrew::Bundle::FlatpakInstaller).to receive(:package_installed?).and_return(false)
  end

  describe "#installed_and_up_to_date?", :needs_linux do
    it "returns false when package is not installed" do
      expect(checker.installed_and_up_to_date?("org.gnome.Calculator")).to be(false)
    end

    it "returns true when package is installed" do
      allow(Homebrew::Bundle::FlatpakInstaller).to receive(:package_installed?).and_return(true)
      expect(checker.installed_and_up_to_date?("org.gnome.Calculator")).to be(true)
    end

    describe "3-tier remote handling" do
      it "checks Tier 1 package with default remote (flathub)" do
        allow(Homebrew::Bundle::FlatpakInstaller).to receive(:package_installed?)
          .with("org.gnome.Calculator", remote: "flathub")
          .and_return(true)

        result = checker.installed_and_up_to_date?(
          { name: "org.gnome.Calculator", options: {} },
        )
        expect(result).to be(true)
      end

      it "checks Tier 1 package with named remote" do
        allow(Homebrew::Bundle::FlatpakInstaller).to receive(:package_installed?)
          .with("org.gnome.Calculator", remote: "fedora")
          .and_return(true)

        result = checker.installed_and_up_to_date?(
          { name: "org.gnome.Calculator", options: { remote: "fedora" } },
        )
        expect(result).to be(true)
      end

      it "checks Tier 2 package with URL remote (resolves to single-app remote)" do
        allow(Homebrew::Bundle::FlatpakInstaller).to receive(:package_installed?)
          .with("org.godotengine.Godot", remote: "org.godotengine.Godot-origin")
          .and_return(true)

        result = checker.installed_and_up_to_date?(
          { name: "org.godotengine.Godot", options: { remote: "https://dl.flathub.org/beta-repo/" } },
        )
        expect(result).to be(true)
      end

      it "checks Tier 2 package with .flatpakref by name only" do
        allow(Homebrew::Bundle::FlatpakInstaller).to receive(:package_installed?)
          .with("org.example.App")
          .and_return(true)

        result = checker.installed_and_up_to_date?(
          { name: "org.example.App", options: { remote: "https://example.com/app.flatpakref" } },
        )
        expect(result).to be(true)
      end

      it "checks Tier 3 package with URL and remote name" do
        allow(Homebrew::Bundle::FlatpakInstaller).to receive(:package_installed?)
          .with("org.godotengine.Godot", remote: "flathub-beta")
          .and_return(true)

        result = checker.installed_and_up_to_date?(
          { name:    "org.godotengine.Godot",
            options: { remote: "flathub-beta", url: "https://dl.flathub.org/beta-repo/" } },
        )
        expect(result).to be(true)
      end
    end
  end

  describe "#failure_reason", :needs_linux do
    it "returns the correct failure message" do
      expect(checker.failure_reason("org.gnome.Calculator", no_upgrade: false))
        .to eq("Flatpak org.gnome.Calculator needs to be installed.")
    end

    it "returns the correct failure message for hash package" do
      expect(checker.failure_reason({ name: "org.gnome.Calculator", options: {} }, no_upgrade: false))
        .to eq("Flatpak org.gnome.Calculator needs to be installed.")
    end
  end

  context "when on macOS", :needs_macos do
    it "flatpak is not available" do
      expect(Homebrew::Bundle.flatpak_installed?).to be(false)
    end
  end
end
