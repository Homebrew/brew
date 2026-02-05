# frozen_string_literal: true

require "bundle"
require "bundle/go_installer"

RSpec.describe Homebrew::Bundle::GoInstaller do
  context "when Go is not installed" do
    before do
      described_class.reset!
      allow(Homebrew::Bundle).to receive(:go_installed?).and_return(false)
    end

    it "tries to install go" do
      expect(Homebrew::Bundle).to \
        receive(:system).with(HOMEBREW_BREW_FILE, "install", "--formula", "go", verbose: false)
                        .and_return(true)
      expect { described_class.preinstall!("github.com/charmbracelet/crush") }.to raise_error(RuntimeError)
    end
  end

  context "when Go is installed" do
    before do
      allow(Homebrew::Bundle).to receive(:go_installed?).and_return(true)
    end

    context "when package is installed" do
      before do
        allow(described_class).to receive(:installed_packages)
          .and_return(["github.com/charmbracelet/crush"])
      end

      it "skips" do
        expect(Homebrew::Bundle).not_to receive(:system)
        expect(described_class.preinstall!("github.com/charmbracelet/crush")).to be(false)
      end
    end

    context "when package is not installed" do
      before do
        allow(Homebrew::Bundle).to receive(:which_go).and_return(Pathname.new("go"))
        allow(described_class).to receive(:installed_packages).and_return([])
      end

      it "installs package" do
        expect(Homebrew::Bundle).to \
          receive(:system).with("go", "install", "github.com/charmbracelet/crush@latest", verbose: false)
                          .and_return(true)
        expect(described_class.preinstall!("github.com/charmbracelet/crush")).to be(true)
        expect(described_class.install!("github.com/charmbracelet/crush")).to be(true)
      end
    end
  end
end
