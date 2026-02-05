# frozen_string_literal: true

require "bundle"
require "bundle/cargo_installer"

RSpec.describe Homebrew::Bundle::CargoInstaller do
  context "when Cargo is not installed" do
    before do
      described_class.reset!
      allow(Homebrew::Bundle).to receive(:cargo_installed?).and_return(false)
    end

    it "tries to install rust" do
      expect(Homebrew::Bundle).to \
        receive(:system).with(HOMEBREW_BREW_FILE, "install", "--formula", "rust", verbose: false)
                        .and_return(true)
      expect { described_class.preinstall!("ripgrep") }.to raise_error(RuntimeError)
    end
  end

  context "when Cargo is installed" do
    before do
      allow(Homebrew::Bundle).to receive(:cargo_installed?).and_return(true)
    end

    context "when package is installed" do
      before do
        allow(described_class).to receive(:installed_packages)
          .and_return(["ripgrep"])
      end

      it "skips" do
        expect(Homebrew::Bundle).not_to receive(:system)
        expect(described_class.preinstall!("ripgrep")).to be(false)
      end
    end

    context "when package is not installed" do
      before do
        allow(Homebrew::Bundle).to receive(:which_cargo).and_return(Pathname.new("/tmp/rust/bin/cargo"))
        allow(described_class).to receive(:installed_packages).and_return([])
      end

      it "installs package" do
        expect(Homebrew::Bundle).to receive(:system) do |*args, verbose:|
          expect(ENV.fetch("PATH", "")).to start_with("/tmp/rust/bin:")
          expect(args).to eq(["/tmp/rust/bin/cargo", "install", "--locked", "ripgrep"])
          expect(verbose).to be(false)
          true
        end
        expect(described_class.preinstall!("ripgrep")).to be(true)
        expect(described_class.install!("ripgrep")).to be(true)
      end
    end
  end
end
