# frozen_string_literal: true

require "bundle"
require "bundle/uv_installer"

RSpec.describe Homebrew::Bundle::UvInstaller do
  context "when uv is not installed" do
    before do
      described_class.reset!
      allow(Homebrew::Bundle).to receive(:uv_installed?).and_return(false)
    end

    it "tries to install uv" do
      expect(Homebrew::Bundle).to \
        receive(:system).with(HOMEBREW_BREW_FILE, "install", "--formula", "uv", verbose: false)
                        .and_return(true)
      expect { described_class.preinstall!("mkdocs") }.to raise_error(RuntimeError)
    end
  end

  context "when uv is installed" do
    before do
      allow(Homebrew::Bundle).to receive(:uv_installed?).and_return(true)
    end

    context "when package is installed with matching options" do
      before do
        allow(described_class).to receive(:installed_packages).and_return([
          {
            name:      "mkdocs",
            specifier: "<2.0",
            with:      ["mkdocs-material<10"],
          },
        ])
      end

      it "skips install" do
        expect(Homebrew::Bundle).not_to receive(:system)
        expect(described_class.preinstall!("mkdocs", specifier: "<2.0", with: ["mkdocs-material<10"])).to be(false)
      end

      it "skips install for package with no options" do
        allow(described_class).to receive(:installed_packages).and_return([
          {
            name:      "ruff",
            specifier: nil,
            with:      [],
          },
        ])

        expect(Homebrew::Bundle).not_to receive(:system)
        expect(described_class.preinstall!("ruff")).to be(false)
      end

      it "treats matching with requirements as installed" do
        allow(described_class).to receive(:installed_packages).and_return([
          {
            name:      "ruff",
            specifier: "<0.15",
            with:      ["httpx>=0.27"],
          },
        ])

        expect(
          described_class.package_installed?(
            "ruff",
            specifier: "<0.15",
            with:      ["httpx>=0.27"],
          ),
        ).to be(true)
      end

      it "treats extras with different ordering as installed" do
        allow(described_class).to receive(:installed_packages).and_return([
          {
            name:      "fastapi[all,standard]",
            specifier: nil,
            with:      [],
          },
        ])

        expect(
          described_class.package_installed?(
            "fastapi[standard,all]",
          ),
        ).to be(true)
      end
    end

    context "when package is installed but options differ" do
      before do
        allow(described_class).to receive(:installed_packages).and_return([
          {
            name:      "mkdocs",
            specifier: "<2.0",
            with:      ["mkdocs-material<10"],
          },
        ])
      end

      it "does not treat mismatched specifier as installed" do
        expect(described_class.package_installed?("mkdocs", specifier: "<1.9")).to be(false)
      end

      it "does not treat mismatched with dependencies as installed" do
        expect(described_class.package_installed?("mkdocs", with: ["mkdocs-material<9"])).to be(false)
      end
    end

    context "when package is not installed" do
      before do
        allow(Homebrew::Bundle).to receive(:which_uv).and_return(Pathname.new("/tmp/uv/bin/uv"))
        allow(described_class).to receive(:installed_packages).and_return([])
      end

      it "installs package with no options" do
        expect(Homebrew::Bundle).to receive(:system)
          .with("/tmp/uv/bin/uv", "tool", "install", "ruff", verbose: false).and_return(true)

        expect(described_class.preinstall!("ruff")).to be(true)
        expect(described_class.install!("ruff")).to be(true)
      end

      it "installs package with all supported options" do
        expect(Homebrew::Bundle).to receive(:system)
          .with("/tmp/uv/bin/uv", "tool", "install", "mkdocs<2.0",
                "--with", "mkdocs-material<10",
                verbose: false).and_return(true)

        expect(described_class.preinstall!("mkdocs", specifier: "<2.0", with: ["mkdocs-material<10"])).to be(true)
        expect(described_class.install!("mkdocs", specifier: "<2.0", with: ["mkdocs-material<10"])).to be(true)
      end
    end
  end
end
