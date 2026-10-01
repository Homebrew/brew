# typed: true
# frozen_string_literal: true

require "bundle"
require "bundle/trust"
require "bundle/dsl"
require "tap"
require "trust"

RSpec.describe Homebrew::Bundle::Trust do
  describe ".entries" do
    def brew_entry(full_name)
      Homebrew::Bundle::Dsl::Entry.new(:brew, full_name, { trusted: true })
    end

    def cask_entry(full_name)
      Homebrew::Bundle::Dsl::Entry.new(:cask, full_name, { trusted: true })
    end

    def tap_entry(name, clone_target = nil, **options)
      options[:clone_target] = clone_target if clone_target
      Homebrew::Bundle::Dsl::Entry.new(:tap, name, options)
    end

    def install_tap(name, remote)
      tap = Tap.fetch(name)
      tap.path.mkpath
      system "git", "-C", tap.path.to_s, "init"
      system "git", "-C", tap.path.to_s, "remote", "add", "origin", remote
      tap
    end

    it "keeps a default-remote tap formula as its tap-qualified name" do
      expect(described_class.entries([brew_entry("defaultremote/foo/bar")]))
        .to eq([[:formula, "defaultremote/foo/bar"]])
    end

    it "ignores an unqualified brew name that maps to no tap" do
      expect(described_class.entries([brew_entry("wget")])).to be_empty
    end

    it "normalises a brew entry to the remote declared by its tap, before the tap is cloned" do
      result = described_class.entries([
        tap_entry("thirdparty/custom", "https://gitlab.com/other/repo"),
        brew_entry("thirdparty/custom/bar"),
      ])

      expect(result).to eq([[:formula, "https://gitlab.com/other/repo/bar"]])
    end

    it "normalises a cask entry to the remote declared by its tap" do
      result = described_class.entries([
        tap_entry("thirdparty/custom", "https://gitlab.com/other/repo"),
        cask_entry("thirdparty/custom/baz"),
      ])

      expect(result).to eq([[:cask, "https://gitlab.com/other/repo/baz"]])
    end

    it "normalises a cask entry written with the homebrew- tap prefix to its declared remote" do
      brewfile = <<~BREWFILE
        tap "thirdparty/homebrew-custom", "https://gitlab.com/other/repo"
        cask "thirdparty/homebrew-custom/baz", trusted: true
      BREWFILE
      entries = Homebrew::Bundle::Dsl.new(StringIO.new(brewfile)).entries

      expect(described_class.entries(entries)).to eq([[:cask, "https://gitlab.com/other/repo/baz"]])
    end

    it "resolves a brew entry independently of the Brewfile order of its tap entry" do
      brew = brew_entry("thirdparty/custom/bar")
      tap = tap_entry("thirdparty/custom", "https://gitlab.com/other/repo")

      expect(described_class.entries([brew, tap])).to eq(described_class.entries([tap, brew]))
    end

    it "collapses a tap trusted-hash item and a brew entry for the same custom-remote item" do
      result = described_class.entries([
        tap_entry("thirdparty/custom", "https://gitlab.com/other/repo", trusted: { formula: "bar" }),
        brew_entry("thirdparty/custom/bar"),
      ])

      expect(result).to eq([[:formula, "https://gitlab.com/other/repo/bar"]])
    end

    it "keeps whole-tap trust keyed to a declared custom remote, not the aliased default it resembles" do
      result = described_class.entries([
        tap_entry("thirdparty/custom", "https://github.com/other/homebrew-project", trusted: true),
      ])

      expect(result).to eq([[:tap, "https://github.com/other/homebrew-project"]])
    end

    it "treats default-remote clone targets in any URL form as the plain tap name" do
      [
        "https://github.com/defaultremote/homebrew-foo",
        "git@github.com:defaultremote/homebrew-foo.git",
        "https://github.com/defaultremote/homebrew-foo.git",
        "https://github.com/defaultremote/homebrew-foo/",
      ].each do |remote|
        result = described_class.entries([
          tap_entry("defaultremote/foo", remote),
          brew_entry("defaultremote/foo/bar"),
        ])

        expect(result).to eq([[:formula, "defaultremote/foo/bar"]])
      end
    end

    it "produces the same entry whether or not the declared custom-remote tap is installed" do
      entries = [
        tap_entry("thirdparty/custom", "https://gitlab.com/other/repo"),
        brew_entry("thirdparty/custom/bar"),
      ]

      untapped = described_class.entries(entries)
      install_tap("thirdparty/custom", "https://gitlab.com/other/repo")
      installed = described_class.entries(entries)

      expect(untapped).to eq([[:formula, "https://gitlab.com/other/repo/bar"]])
      expect(installed).to eq(untapped)
    ensure
      FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
    end

    # Keyed verbatim (here including `.git`) so bundle, installed-name `brew trust`, and the items.sh
    # shell filter all match the same raw origin; normalising only the declared remote would diverge.
    it "keys a custom-remote brew entry identically whether its remote is declared or installed" do
      remote = "https://gitlab.com/other/repo.git"

      declared = described_class.entries([
        tap_entry("thirdparty/custom", remote),
        brew_entry("thirdparty/custom/bar"),
      ])
      install_tap("thirdparty/custom", remote)
      installed = described_class.entries([brew_entry("thirdparty/custom/bar")])

      expect(declared).to eq([[:formula, "https://gitlab.com/other/repo.git/bar"]])
      expect(installed).to eq(declared)
    ensure
      FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
    end

    it "uses the installed remote for an installed custom tap with no declared clone target" do
      install_tap("thirdparty/custom", "https://gitlab.com/other/repo")

      expect(described_class.entries([tap_entry("thirdparty/custom", trusted: true)]))
        .to eq([[:tap, "https://gitlab.com/other/repo"]])
      expect(described_class.entries([tap_entry("thirdparty/custom", trusted: { formula: "bar" })]))
        .to eq([[:formula, "https://gitlab.com/other/repo/bar"]])
    ensure
      FileUtils.rm_rf HOMEBREW_TAP_DIRECTORY/"thirdparty"
    end

    it "raises on unsupported trusted keys" do
      expect do
        described_class.entries([tap_entry("thirdparty/custom", trusted: { bogus: "bar" })])
      end.to raise_error(UsageError, /Unsupported trusted keys/)
    end
  end
end
