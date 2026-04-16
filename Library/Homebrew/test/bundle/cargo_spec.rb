# typed: false
# frozen_string_literal: true

require "bundle"
require "bundle/dsl"
require "bundle/extensions/cargo"

RSpec.describe Homebrew::Bundle::Cargo do
  around do |example|
    with_env({
      "HOMEBREW_CARGO_HOME"         => "~/.cargo",
      "HOMEBREW_CARGO_INSTALL_ROOT" => "~/.cargo/bin",
      "HOMEBREW_RUSTUP_HOME"        => "~/.rustup",
      "CARGO_HOME"                  => nil,
      "CARGO_INSTALL_ROOT"          => nil,
      "RUSTUP_HOME"                 => nil,
    }) do
      example.run
    end
  end

  describe "dumping" do
    subject(:dumper) { described_class }

    context "when cargo is not installed" do
      before do
        described_class.reset!
        allow(described_class).to receive(:package_manager_executable).and_return(nil)
      end

      it "returns an empty list" do
        expect(dumper.packages).to be_empty
      end

      it "dumps an empty string" do # rubocop:todo RSpec/AggregateExamples
        expect(dumper.dump).to eql("")
      end
    end

    context "when cargo is installed" do
      before do
        described_class.reset!
        allow(described_class).to receive(:package_manager_executable).and_return(Pathname.new("cargo"))
      end

      it "returns package list" do
        expect(described_class).to receive(:`).with("cargo install --list") do
          expect(ENV.fetch("CARGO_HOME", nil)).to eq("~/.cargo")
          expect(ENV.fetch("CARGO_INSTALL_ROOT", nil)).to eq("~/.cargo/bin")
          expect(ENV.fetch("RUSTUP_HOME", nil)).to eq("~/.rustup")
          <<~EOS
            ripgrep v13.0.0:
                rg
            bat v0.24.0 (/Users/test/.cargo/bin/bat)
          EOS
        end

        expect(dumper.packages).to eql(%w[ripgrep bat])
      end

      it "dumps package list" do
        allow(dumper).to receive(:packages).and_return(["ripgrep", "bat"])
        expect(dumper.dump).to eql("cargo \"ripgrep\"\ncargo \"bat\"")
      end
    end
  end

  describe "installing" do
    context "when Cargo is not installed" do
      before do
        described_class.reset!
        allow(described_class).to receive(:package_manager_executable).and_return(nil)
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
        allow(described_class).to receive(:package_manager_executable).and_return(Pathname.new("cargo"))
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
          allow(described_class).to receive_messages(package_manager_executable: Pathname.new("/tmp/rust/bin/cargo"),
                                                     installed_packages:         [])
        end

        it "installs package" do
          expect(Homebrew::Bundle).to receive(:system) do |*args, verbose:|
            expect(ENV.fetch("CARGO_HOME", nil)).to eq("~/.cargo")
            expect(ENV.fetch("CARGO_INSTALL_ROOT", nil)).to eq("~/.cargo/bin")
            expect(ENV.fetch("RUSTUP_HOME", nil)).to eq("~/.rustup")
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

  describe "cleanup" do
    before do
      described_class.reset!
      allow(described_class).to receive_messages(
        package_manager_executable: Pathname.new("/tmp/rust/bin/cargo"),
        packages:                   %w[ripgrep fd-find bat],
        installed_packages:         %w[ripgrep fd-find bat],
      )
    end

    it "returns packages not in Brewfile entries" do
      entries = [Homebrew::Bundle::Dsl::Entry.new(:cargo, "ripgrep")]
      expect(described_class.cleanup_items(entries)).to eql(%w[fd-find bat])
    end

    it "returns frozen empty array when cargo is not installed" do
      allow(described_class).to receive(:package_manager_installed?).and_return(false)
      entries = [Homebrew::Bundle::Dsl::Entry.new(:cargo, "ripgrep")]
      expect(described_class.cleanup_items(entries)).to eql([])
    end
  end
end
