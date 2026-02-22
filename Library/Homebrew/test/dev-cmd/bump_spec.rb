# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "bump_version_parser"
require "dev-cmd/bump"

RSpec.describe Homebrew::DevCmd::Bump do
  subject(:bump) { described_class.new(["test"]) }

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

  it "gives an error for `--tap` with official taps", :integration_test do
    expect { brew "bump", "--tap", "Homebrew/core" }
      .to output(/Invalid usage/).to_stderr
      .and not_to_output.to_stdout
      .and be_a_failure
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
end
