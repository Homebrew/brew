# frozen_string_literal: true

require "ostruct"
require "bundle"
require "bundle/skipper"
require "bundle/dsl"

RSpec.describe Homebrew::Bundle::Skipper do
  subject(:skipper) { described_class }

  before do
    allow(ENV).to receive(:[]).and_return(nil)
    allow(ENV).to receive(:[]).with("HOMEBREW_BUNDLE_BREW_SKIP").and_return("mysql")
    allow(ENV).to receive(:[]).with("HOMEBREW_BUNDLE_TAP_SKIP").and_return("org/repo")
    allow(Formatter).to receive(:warning)
    skipper.instance_variable_set(:@skipped_entries, nil)
    skipper.instance_variable_set(:@failed_taps, nil)
  end

  describe ".skip?" do
    context "with a listed formula" do
      let(:entry) { Homebrew::Bundle::Dsl::Entry.new(:brew, "mysql") }

      it "returns true" do
        expect(skipper.skip?(entry)).to be true
      end
    end

    context "with an unbottled formula on ARM" do
      let(:entry) { Homebrew::Bundle::Dsl::Entry.new(:brew, "mysql") }

      it "returns true" do
        allow(Hardware::CPU).to receive(:arm?).and_return(true)
        allow(Homebrew).to receive(:default_prefix?).and_return(true)
        stub_formula_loader formula("mysql") { url "mysql-1.0" }

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
        expect($stdout).to receive(:puts).with(
          Formatter.warning("Skipping flatpak org.gnome.Calculator (unsupported on macOS)"),
        )
        expect(skipper.skip?(entry)).to be true
      end

      it "skips silently when silent flag is set" do
        expect($stdout).not_to receive(:puts)
        expect(skipper.skip?(entry, silent: true)).to be true
      end
    end

    context "with a flatpak entry on Linux", :needs_linux do
      let(:entry) { Homebrew::Bundle::Dsl::Entry.new(:flatpak, "org.gnome.Calculator") }

      it "does not skip" do
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
