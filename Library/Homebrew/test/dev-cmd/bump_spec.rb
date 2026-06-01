# typed: true
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "bump_version_parser"
require "dev-cmd/bump"

RSpec.describe Homebrew::DevCmd::Bump do
  subject(:bump) { klass.new(["test"]) }

  let(:klass) { Homebrew::DevCmd::Bump }
  let(:f_basic) do
    formula("basic_formula") do
      desc "Basic formula"
      url "https://brew.sh/test-1.2.3.tgz"
    end
  end
  let(:c_basic) do
    Cask::CaskLoader.load(+<<-RUBY)
      cask "basic_cask" do
        version "1.2.3"

        name "Basic Cask"
        desc "Basic cask"
      end
    RUBY
  end
  let(:c_latest) do
    Cask::CaskLoader.load(+<<-RUBY)
      cask "latest_cask" do
        version :latest
        sha256 :no_check

        url "https://brew.sh/test.dmg"
        name "Latest Cask"
        desc "Latest cask"
        homepage "https://brew.sh"
      end
    RUBY
  end

  it_behaves_like "parseable arguments"

  describe "formula", :integration_test, :needs_homebrew_curl, :needs_network do
    it "returns no data and prints a message for HEAD-only formulae" do
      content = <<~RUBY
        desc "HEAD-only test formula"
        homepage "https://brew.sh"
        head "https://github.com/Homebrew/brew.git", branch: "main"
      RUBY
      setup_test_formula("headonly", content)

      expect { brew "bump", "headonly" }
        .to output(/Formula is HEAD-only./).to_stdout
        .and not_to_output.to_stderr
        .and be_a_success
    end
  end

  it "gives an error for `--tap` with official taps" do
    allow(Homebrew).to receive(:install_bundler_gems!)

    expect { klass.new(["--tap", "Homebrew/core"]).run }
      .to raise_error(UsageError, /`--tap` requires `--auto` for official taps/)
  end

  describe "::skip_ineligible_formulae!" do
    it "prints a legible message for casks using `version :latest`" do
      expect { expect(bump.send(:skip_ineligible_formulae!, c_latest)).to be(true) }
        .to output(/Cask uses `version :latest` so `brew bump` cannot check it\./).to_stdout
        .and not_to_output.to_stderr
    end
  end

  describe "::compare_versions" do
    it "returns a hash with `:multiple_versions` and `:newer_than_upstream` values" do
      general_version = Homebrew::BumpVersionParser.new(general: Version.new("1.2.3"))
      arm_intel_version = Homebrew::BumpVersionParser.new(
        arm:   Version.new("1.2.3"),
        intel: Version.new("1.2.2"),
      )
      arm_intel_version_higher = Homebrew::BumpVersionParser.new(
        arm:   Version.new("1.2.4"),
        intel: Version.new("1.2.2"),
      )

      # Message strings are naively parsed as cask versions but this should be
      # reworked so we can easily distinguish messages from real cask versions
      skipped = Homebrew::BumpVersionParser.new(
        general: Cask::DSL::Version.new("skipped"),
      )
      arm_version_intel_skipped = Homebrew::BumpVersionParser.new(
        arm:   Version.new("1.2.3"),
        intel: Cask::DSL::Version.new("skipped"),
      )
      unable_to_get_versions = Homebrew::BumpVersionParser.new(
        general: Cask::DSL::Version.new("unable to get versions"),
      )
      unable_to_get_throttled_versions = Homebrew::BumpVersionParser.new(
        general: Cask::DSL::Version.new("unable to get throttled versions"),
      )

      # Compare the same version types when shared by current/new versions
      expect(bump.send(:compare_versions, general_version, general_version, f_basic)).to eq({
        multiple_versions:   { current: false, new: false },
        newer_than_upstream: { general: false },
      })
      expect(bump.send(:compare_versions, general_version, general_version, c_basic)).to eq({
        multiple_versions:   { current: false, new: false },
        newer_than_upstream: { general: false },
      })
      expect(bump.send(:compare_versions, arm_intel_version, arm_intel_version, c_basic)).to eq({
        multiple_versions:   { current: true, new: true },
        newer_than_upstream: { arm: false, intel: false },
      })

      # Compare current versions to new version when the current version differs
      # by arch but the new version does not
      expect(bump.send(:compare_versions, arm_intel_version, general_version, c_basic)).to eq({
        multiple_versions:   { current: true, new: false },
        newer_than_upstream: { arm: false, intel: false },
      })

      # Compare current version to the highest new version when the
      # current version does not differ by arch but the new version does
      expect(bump.send(:compare_versions, general_version, arm_intel_version, c_basic)).to eq({
        multiple_versions:   { current: false, new: true },
        newer_than_upstream: { general: false },
      })
      expect(bump.send(:compare_versions, general_version, arm_intel_version_higher, c_basic)).to eq({
        multiple_versions:   { current: false, new: true },
        newer_than_upstream: { general: false },
      })
      expect(bump.send(:compare_versions, general_version, arm_version_intel_skipped, c_basic)).to eq({
        multiple_versions:   { current: false, new: true },
        newer_than_upstream: { general: false },
      })

      # Default to `false` when the new version is a message rather than a
      # version
      expect(bump.send(:compare_versions, general_version, skipped, c_basic)).to eq({
        multiple_versions:   { current: false, new: false },
        newer_than_upstream: { general: false },
      })
      expect(bump.send(:compare_versions, general_version, unable_to_get_versions, c_basic)).to eq({
        multiple_versions:   { current: false, new: false },
        newer_than_upstream: { general: false },
      })
      expect(bump.send(:compare_versions, general_version, unable_to_get_throttled_versions, c_basic)).to eq({
        multiple_versions:   { current: false, new: false },
        newer_than_upstream: { general: false },
      })
    end
  end

  describe "::retrieve_and_display_info_and_open_pr" do
    subject(:bump) { klass.new(["--open-pr", "test"]) }

    before do
      allow(bump).to receive(:retrieve_pull_requests)
      allow(GitHub).to receive(:too_many_open_prs?).and_return(false)
    end

    it "passes arch-specific version arguments when a cask moves from one version to arch-specific versions" do
      version_info = klass::VersionBumpInfo.new(
        type:                          :cask,
        deprecated:                    { general: false },
        multiple_versions:             { current: false, new: true },
        version_name:                  "cask version:   ",
        current_version:               Homebrew::BumpVersionParser.new(general: Version.new("1.2.3")),
        new_version:                   Homebrew::BumpVersionParser.new(
          arm:   Version.new("1.2.5"),
          intel: Version.new("1.2.4"),
        ),
        repology_latest:               "not found",
        newer_than_upstream:           { general: false },
        duplicate_pull_requests:       nil,
        maybe_duplicate_pull_requests: nil,
      )
      allow(bump).to receive(:retrieve_versions_by_arch).and_return(version_info)

      expect(bump).to receive(:system).with(
        HOMEBREW_BREW_FILE,
        "bump-cask-pr",
        "basic-cask",
        "--version-arm=1.2.5",
        "--version-intel=1.2.4",
        "--no-browse",
        "--message=Created by `brew bump`",
      ).and_return(true)

      bump.send(:retrieve_and_display_info_and_open_pr, c_basic, "basic-cask", [], ambiguous_cask: false)
    end

    it "passes a single version argument when an arch-specific cask moves to one version" do
      version_info = klass::VersionBumpInfo.new(
        type:                          :cask,
        deprecated:                    { arm: false, intel: false },
        multiple_versions:             { current: true, new: false },
        version_name:                  "cask version:   ",
        current_version:               Homebrew::BumpVersionParser.new(
          arm:   Version.new("1.2.3"),
          intel: Version.new("1.2.2"),
        ),
        new_version:                   Homebrew::BumpVersionParser.new(general: Version.new("1.2.4")),
        repology_latest:               "not found",
        newer_than_upstream:           { arm: false, intel: false },
        duplicate_pull_requests:       nil,
        maybe_duplicate_pull_requests: nil,
      )
      allow(bump).to receive(:retrieve_versions_by_arch).and_return(version_info)

      expect(bump).to receive(:system).with(
        HOMEBREW_BREW_FILE,
        "bump-cask-pr",
        "basic-cask",
        "--version-arm=1.2.4",
        "--version-intel=1.2.4",
        "--no-browse",
        "--message=Created by `brew bump`",
      ).and_return(true)

      bump.send(:retrieve_and_display_info_and_open_pr, c_basic, "basic-cask", [], ambiguous_cask: false)
    end
  end

  describe "::message?" do
    let(:version) { Version.new("1.2.3") }
    let(:cask_version) { Cask::DSL::Version.new("1.2.3,4") }
    let(:message_strings) do
      [
        "error: message",
        "skipped",
        "skipped - deprecated",
        "unable to get versions",
        "unable to get throttled versions",
      ]
    end

    it "returns false when value is not a `Cask::DSL::Version` or string" do
      expect(bump.send(:message?, version)).to be(false)
      expect(bump.send(:message?, nil)).to be(false)
    end

    it "returns false when `Cask::DSL::Version` or string is not a message" do
      expect(bump.send(:message?, cask_version)).to be(false)
      expect(bump.send(:message?, "Not a message string")).to be(false)
    end

    it "returns true when `Cask::DSL::Version` or string is a message" do
      message_strings.each do |message_string|
        expect(bump.send(:message?, Cask::DSL::Version.new(message_string))).to be(true)
        expect(bump.send(:message?, message_string)).to be(true)
      end
    end
  end

  describe "::version_args_for_bump" do
    let(:current_general) { Homebrew::BumpVersionParser.new(general: "26.519.41501") }
    let(:new_split) do
      Homebrew::BumpVersionParser.new(
        arm:   "26.519.81530",
        intel: "26.519.41501",
      )
    end
    let(:current_split) do
      Homebrew::BumpVersionParser.new(
        arm:   "1.2.3",
        intel: "1.2.2",
      )
    end
    let(:new_general) { Homebrew::BumpVersionParser.new(general: "1.2.4") }

    it "emits only changed arch arguments when a general cask version becomes arch-specific" do
      expect(
        bump.send(:version_args_for_bump,
                  current_version:   current_general,
                  new_version:       new_split,
                  multiple_versions: { current: false, new: true },
                  name:              "codex-app"),
      ).to eq(["--version-arm=26.519.81530"])
    end

    it "emits arch arguments for both architectures when split cask versions merge" do
      expect(
        bump.send(:version_args_for_bump,
                  current_version:   current_split,
                  new_version:       new_general,
                  multiple_versions: { current: true, new: false },
                  name:              "foo"),
      ).to eq(["--version-arm=1.2.4", "--version-intel=1.2.4"])
    end

    it "keeps existing split-to-split routing" do
      new_split = Homebrew::BumpVersionParser.new(
        arm:   "1.2.4",
        intel: "1.2.2",
      )

      expect(
        bump.send(:version_args_for_bump,
                  current_version:   current_split,
                  new_version:       new_split,
                  multiple_versions: { current: true, new: true },
                  name:              "foo"),
      ).to eq(["--version-arm=1.2.4"])
    end

    it "keeps existing general version routing" do
      expect(
        bump.send(:version_args_for_bump,
                  current_version:   current_general,
                  new_version:       new_general,
                  multiple_versions: { current: false, new: false },
                  name:              "foo"),
      ).to eq(["--version=1.2.4"])
    end

    it "ignores message versions in arch-specific routing" do
      new_split = Homebrew::BumpVersionParser.new(
        arm:   "26.519.81530",
        intel: "skipped",
      )

      expect(
        bump.send(:version_args_for_bump,
                  current_version:   current_general,
                  new_version:       new_split,
                  multiple_versions: { current: false, new: true },
                  name:              "foo"),
      ).to eq(["--version-arm=26.519.81530"])
    end
  end

  describe "::version_with_cooldown" do
    it "uses RubyGems version creation times" do
      version_info = {
        latest: "1.2.4",
        meta:   {
          strategy: "RubyGems",
          url:      {
            original: "https://rubygems.org/downloads/example-package-1.2.3.gem",
            strategy: "https://rubygems.org/api/v1/versions/example-package/latest.json",
          },
        },
      }
      content = <<~JSON
        [
          {
            "created_at": "2026-04-04T00:00:00.000Z",
            "number": "1.2.4",
            "platform": "ruby",
            "prerelease": false
          },
          {
            "created_at": "2026-04-02T00:00:00.000Z",
            "number": "1.2.3",
            "platform": "ruby",
            "prerelease": false
          }
        ]
      JSON

      allow(DateTime).to receive(:now).and_return(DateTime.parse("2026-04-04T12:00:00Z"))
      allow(Utils::Curl).to receive(:curl_output)
        .with(
          "--compressed",
          "--fail-with-body",
          "--location",
          "--max-redirs",
          "5",
          "--silent",
          "https://rubygems.org/api/v1/versions/example-package.json",
          connect_timeout: 15,
          max_time:        55,
          retries:         0,
          timeout:         60,
        )
        .and_return([content, "", instance_double(Process::Status, success?: true)])

      expect(bump.send(:version_with_cooldown, version_info, Version.new("1.2.2"))).to eq(Version.new("1.2.3"))
    end

    it "uses platform-specific RubyGems releases for native gems" do
      version_info = {
        latest: "1.2.4",
        meta:   {
          strategy: "RubyGems",
          url:      {
            original: "https://rubygems.org/downloads/example-package-1.2.3-arm64-darwin.gem",
            strategy: "https://rubygems.org/api/v1/versions/example-package/latest.json",
          },
        },
      }
      content = <<~JSON
        [
          {
            "created_at": "2026-04-04T00:00:00.000Z",
            "number": "1.2.4",
            "platform": "arm64-darwin",
            "prerelease": false
          },
          {
            "created_at": "2026-04-02T00:00:00.000Z",
            "number": "1.2.3",
            "platform": "arm64-darwin",
            "prerelease": false
          },
          {
            "created_at": "2026-03-01T00:00:00.000Z",
            "number": "1.2.4",
            "platform": "ruby",
            "prerelease": false
          },
          {
            "created_at": "2026-02-01T00:00:00.000Z",
            "number": "1.2.3",
            "platform": "ruby",
            "prerelease": false
          }
        ]
      JSON

      allow(DateTime).to receive(:now).and_return(DateTime.parse("2026-04-04T12:00:00Z"))
      allow(Utils::Curl).to receive(:curl_output)
        .with(
          "--compressed",
          "--fail-with-body",
          "--location",
          "--max-redirs",
          "5",
          "--silent",
          "https://rubygems.org/api/v1/versions/example-package.json",
          connect_timeout: 15,
          max_time:        55,
          retries:         0,
          timeout:         60,
        )
        .and_return([content, "", instance_double(Process::Status, success?: true)])

      expect(bump.send(:version_with_cooldown, version_info, Version.new("1.2.2"))).to eq(Version.new("1.2.3"))
    end
  end
end
