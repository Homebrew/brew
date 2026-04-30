# typed: false
# frozen_string_literal: true

require "bundle/dsl"
require "bundle/locker"
require "bundle/package_types"
require "cask/cask_loader"

RSpec.describe Homebrew::Bundle::Locker do
  let(:brewfile_path) { mktmpdir/"Brewfile" }
  let(:brew_entry) do
    instance_double(Homebrew::Bundle::Dsl::Entry, type: :brew, name: "ruby", options: { args: ["with-yjit"] })
  end
  let(:cask_entry) do
    instance_double(Homebrew::Bundle::Dsl::Entry, type: :cask, name: "firefox", options: {})
  end

  before do
    allow(Homebrew::Bundle).to receive(:installable).with(:brew).and_return(Homebrew::Bundle::Brew)
    allow(Homebrew::Bundle).to receive(:installable).with(:cask).and_return(Homebrew::Bundle::Cask)
    allow(Homebrew::Bundle::Brew).to receive(:lock_entry)
      .with("ruby", { args: ["with-yjit"] })
      .and_return({ "name" => "ruby", "version" => "3.4.2" })
    allow(Homebrew::Bundle::Cask).to receive(:lock_entry)
      .with("firefox", {})
      .and_return({ "name" => "firefox", "version" => "139.0.1" })
  end

  it "writes a lockfile with version 1 schema" do
    lockfile_path = described_class.lock(entries: [brew_entry, cask_entry], file: brewfile_path)

    expect(JSON.parse(lockfile_path.read)).to eq({
      "entries"          => {
        "brew" => {
          "ruby" => {
            "name"    => "ruby",
            "version" => "3.4.2",
          },
        },
        "cask" => {
          "firefox" => {
            "name"    => "firefox",
            "version" => "139.0.1",
          },
        },
        "tap"  => {},
      },
      "homebrew_version" => HOMEBREW_VERSION,
      "version"          => 1,
    })
    expect(lockfile_path).to eq(brewfile_path.dirname/"Brewfile.lock.json")
  end

  it "produces deterministic output" do
    first_lockfile_path = described_class.lock(entries: [cask_entry, brew_entry], file: brewfile_path)
    first_contents = first_lockfile_path.read

    second_lockfile_path = described_class.lock(entries: [brew_entry, cask_entry], file: brewfile_path)

    expect(second_lockfile_path.read).to eq(first_contents)
  end

  it "writes atomically via temp file and rename" do
    lockfile_path = described_class.lock_path(brewfile_path)
    expect(File).to receive(:rename).with(a_string_matching(/Brewfile\.lock\.json.*\.tmp/), lockfile_path)
                                    .and_call_original

    described_class.lock(entries: [brew_entry], file: brewfile_path)
  end

  it "reads existing lockfiles" do
    described_class.lock(entries: [brew_entry], file: brewfile_path)

    expect(described_class.read(file: brewfile_path)).to include("version" => 1)
  end

  it "falls back to Brewfile identity for missing package data" do
    expect(Homebrew::Bundle::PackageType.lock_entry("ruby", args: ["with-yjit"])).to eq({
      "name"    => "ruby",
      "options" => { "args" => ["with-yjit"] },
    })
  end

  it "returns formula version, revision and bottle identity" do
    allow(Homebrew::Bundle::Brew).to receive(:find_formula).with("ruby").and_return({
      version: "3.4.2",
      bottle:  {
        files: {
          arm64_sequoia: {
            sha256: "def456",
            url:    "https://ghcr.io/v2/homebrew/core/ruby/blobs/sha256:def456",
          },
        },
      },
    })
    allow(Homebrew::Bundle::Brew).to receive(:formula_revision).with("ruby").and_return(1)

    expect(Homebrew::Bundle::Brew.lock_entry("ruby")).to eq({
      "name"     => "ruby",
      "version"  => "3.4.2",
      "revision" => 1,
      "bottle"   => {
        "url"    => "https://ghcr.io/v2/homebrew/core/ruby/blobs/sha256:def456",
        "sha256" => "def456",
      },
    })
  end

  it "returns cask version and sha256 identity" do
    cask = instance_double(Cask::Cask, version: "139.0.1", sha256: "abc123")
    allow(Cask::CaskLoader).to receive(:load).with("firefox").and_return(cask)

    expect(Homebrew::Bundle::Cask.lock_entry("firefox")).to eq({
      "name"    => "firefox",
      "version" => "139.0.1",
      "sha256"  => "abc123",
    })
  end

  it "returns tap remote and branch identity" do
    tap = instance_double(Tap, remote: "https://github.com/Homebrew/homebrew-cask", git_branch: "master")
    allow(Tap).to receive(:fetch).with("homebrew/cask").and_return(tap)

    expect(Homebrew::Bundle::Tap.lock_entry("homebrew/cask")).to eq({
      "name"   => "homebrew/cask",
      "remote" => "https://github.com/Homebrew/homebrew-cask",
      "branch" => "master",
    })
  end

  it "does not probe extension package versions in phase 1" do
    expect(Homebrew::Bundle::Cargo.lock_entry("ripgrep")).to eq({
      "name" => "ripgrep",
    })
  end
end
