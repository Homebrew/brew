# typed: true
# frozen_string_literal: true

require "bundle"
require "bundle/skipper"
require "bundle/dsl"

RSpec.describe Homebrew::Bundle::Skipper do
  subject(:skipper) { described_class }

  before do
    allow(ENV).to receive(:[]).and_return(nil)
    allow(ENV).to receive(:[]).with("HOMEBREW_BUNDLE_BREW_SKIP").and_return("mysql")
    allow(ENV).to receive(:[]).with("HOMEBREW_BUNDLE_TAP_SKIP").and_return("org/repo")
    skipper.skipped_entries = nil
    skipper.failed_taps = nil
  end

  describe ".skip?" do
    context "with a listed formula" do
      let(:entry) { Homebrew::Bundle::Dsl::Entry.new(:brew, "mysql") }

      it "returns true" do
        expect(skipper.skip?(entry)).to be true
      end

      it "warns on stderr" do
        expect { skipper.skip?(entry) }.to output(/Skipping mysql/).to_stderr.and not_to_output.to_stdout
      end

      it "warns without a GitHub Actions annotation" do
        ENV["GITHUB_ACTIONS"] = "1"
        ENV.delete("HOMEBREW_TESTS")
        expect { skipper.skip?(entry) }.to output(/^Warning: Skipping mysql/).to_stderr
      end
    end

    context "with an unbottled formula on ARM" do
      let(:entry) { Homebrew::Bundle::Dsl::Entry.new(:brew, "mysql") }

      it "returns true" do
        allow(Hardware::CPU).to receive(:arm?).and_return(true)
        allow(Homebrew).to receive(:default_prefix?).and_return(true)
        stub_formula_loader formula("mysql") {
          T.bind(self, T.class_of(Formula))
          url "mysql-1.0"
        }

        expect(skipper.skip?(entry)).to be true
      end
    end

    context "with an unlisted cask", :needs_macos do
      let(:entry) { Homebrew::Bundle::Dsl::Entry.new(:cask, "java") }

      it "returns false" do
        expect(skipper.skip?(entry)).to be false
      end
    end

    context "with a flatpak entry", :needs_macos do
      let(:entry) { Homebrew::Bundle::Dsl::Entry.new(:flatpak, "org.gnome.Calculator") }

      it "skips on macOS with warning" do
        expect { skipper.skip?(entry) }
          .to output(/Skipping flatpak org\.gnome\.Calculator \(unsupported on macOS\)/).to_stderr
      end
    end

    context "with a WinGet entry", :needs_macos do
      let(:entry) { Homebrew::Bundle::Dsl::Entry.new(:winget, "Valve.Steam") }

      it "skips on macOS with warning" do
        expect { skipper.skip?(entry) }.to output(/Skipping winget Valve\.Steam \(requires WSL\)/).to_stderr
      end
    end

    context "with a flatpak entry on Linux", :needs_linux do
      let(:entry) { Homebrew::Bundle::Dsl::Entry.new(:flatpak, "org.gnome.Calculator") }

      it "does not skip" do
        expect(skipper.skip?(entry)).to be false
      end
    end

    context "with a WinGet entry on Linux outside WSL", :needs_linux do
      let(:entry) { Homebrew::Bundle::Dsl::Entry.new(:winget, "App Installer") }

      it "skips with warning" do
        allow(OS).to receive(:wsl?).and_return(false)
        expect { skipper.skip?(entry) }.to output(/Skipping winget App Installer \(requires WSL\)/).to_stderr
      end
    end

    context "with a WinGet entry on WSL", :needs_linux do
      let(:entry) { Homebrew::Bundle::Dsl::Entry.new(:winget, "App Installer") }

      it "does not skip" do
        allow(OS).to receive(:wsl?).and_return(true)
        expect(skipper.skip?(entry)).to be false
      end
    end

    context "with a cask that requires macOS", :needs_linux do
      let(:entry) { Homebrew::Bundle::Dsl::Entry.new(:cask, "testball") }

      it "skips on Linux with warning" do
        allow(Cask::CaskLoader).to receive(:load).with("testball").and_return(
          instance_double(Cask::Cask, supports_linux?: false),
        )
        expect { skipper.skip?(entry) }.to output(/Skipping cask testball \(requires macOS\)/).to_stderr
      end
    end

    context "with a platform-agnostic cask on Linux", :needs_linux do
      let(:entry) { Homebrew::Bundle::Dsl::Entry.new(:cask, "testball") }

      it "does not skip" do
        allow(Cask::CaskLoader).to receive(:load).with("testball").and_return(
          instance_double(Cask::Cask, supports_linux?: true),
        )
        expect(skipper.skip?(entry)).to be false
      end
    end

    context "with a cask from an untapped tap on Linux", :needs_linux do
      let(:entry) do
        Homebrew::Bundle::Dsl::Entry.new(:cask, "vscodium-linux", full_name: "ublue-os/tap/vscodium-linux")
      end

      it "does not skip when cask can't be loaded" do
        allow(Cask::CaskLoader).to receive(:load).with("vscodium-linux").and_raise(Cask::CaskUnavailableError.new("vscodium-linux"))
        expect(skipper.skip?(entry)).to be false
      end
    end

    context "with a listed formula in a failed tap" do
      let(:entry) { Homebrew::Bundle::Dsl::Entry.new(:brew, "org/repo/formula") }

      it "returns true" do
        skipper.tap_failed!("org/repo")

        expect(skipper.skip?(entry)).to be true
      end
    end
  end

  describe ".failed_tap!" do
    context "with a tap" do
      let(:tap) { Homebrew::Bundle::Dsl::Entry.new(:tap, "org/repo-b") }
      let(:entry) { Homebrew::Bundle::Dsl::Entry.new(:brew, "org/repo-b/formula") }

      it "returns false" do
        expect(skipper.skip?(entry)).to be false

        skipper.tap_failed! tap.name

        expect(skipper.skip?(entry)).to be true
      end
    end
  end
end
