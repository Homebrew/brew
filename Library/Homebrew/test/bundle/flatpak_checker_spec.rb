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
  end

  describe "#failure_reason", :needs_linux do
    it "returns the correct failure message" do
      expect(checker.failure_reason("org.gnome.Calculator", no_upgrade: false))
        .to eq("Flatpak org.gnome.Calculator needs to be installed.")
    end
  end

  context "when on macOS", :needs_macos do
    it "flatpak is not available" do
      expect(Homebrew::Bundle.flatpak_installed?).to be(false)
    end
  end
end
