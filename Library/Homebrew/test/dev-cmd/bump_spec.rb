# typed: true
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "bump_version_parser"
require "dev-cmd/bump"

RSpec.describe Homebrew::DevCmd::Bump do
  subject(:bump) { described_class.new(["test"]) }

  let(:f_basic) do
    formula("basic_formula") do
      T.bind(self, T.class_of(Formula))
      desc "Basic formula"
      url "https://brew.sh/test-1.2.3.tgz"
    end
  end
  let(:f_disabled) do
    formula("disabled_formula") do
      T.bind(self, T.class_of(Formula))
      desc "Disabled formula"
      url "https://brew.sh/test-1.2.3.tgz"

      disable! date: "2020-01-01", because: "Testing"
    end
  end
  let(:f_partially_disabled_arch) do
    path = mktmpdir/"partially_disabled_arch_formula.rb"
    path.write <<~RUBY
      class PartiallyDisabledArchFormula < Formula
        desc "Partially disabled (arch) formula"
        url "https://brew.sh/test-1.2.3.tgz"

        on_#{Hardware::CPU.arm? ? "arm" : "intel"} do
          disable! date: "2020-01-01", because: "Testing"
        end
      end
    RUBY

    Formulary.factory(path)
  end
  let(:f_partially_disabled_os) do
    path = mktmpdir/"partially_disabled_os_formula.rb"
    path.write <<~RUBY
      class PartiallyDisabledOsFormula < Formula
        desc "Partially disabled (OS) formula"
        url "https://brew.sh/test-1.2.3.tgz"

        on_#{OS.mac? ? "macos" : "linux"} do
          disable! date: "2020-01-01", because: "Testing"
        end
      end
    RUBY

    Formulary.factory(path)
  end
  let(:f_head_only) do
    formula("head_only_formula") do
      T.bind(self, T.class_of(Formula))
      desc "HEAD-only formula"
      head "https://github.com/Homebrew/brew.git", branch: "main"
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
  let(:c_disabled) do
    Cask::CaskLoader.load(+<<-RUBY)
      cask "disabled_cask" do
        version "1.2.3"

        name "Disabled Cask"
        desc "Disabled cask"

        disable! date: "2020-01-01", because: "Testing"
      end
    RUBY
  end
  let(:c_partially_disabled_arch) do
    Cask::CaskLoader.load(<<~RUBY)
      cask "partially_disabled_arch_cask" do
        version "1.2.3"

        name "Partially Disabled Arch Cask"
        desc "Partially disabled (arch) cask"

        on_#{Hardware::CPU.arm? ? "arm" : "intel"} do
          disable! date: "2020-01-01", because: "Testing"
        end
      end
    RUBY
  end
  let(:c_partially_disabled_os) do
    Cask::CaskLoader.load(<<~RUBY)
      cask "partially_disabled_os_cask" do
        version "1.2.3"

        name "Partially Disabled OS Cask"
        desc "Partially disabled (OS) cask"

        on_#{OS.mac? ? "macos" : "linux"} do
          disable! date: "2020-01-01", because: "Testing"
        end
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

  describe "formula and cask", :cask, :integration_test do
    it "prints messages for HEAD-only Formulae and latest Casks" do
      content = <<~RUBY
        desc "HEAD-only test formula"
        homepage "https://brew.sh"
        head "https://github.com/Homebrew/brew.git", branch: "main"
      RUBY
      setup_test_formula("headonly", content)

      expect { brew "bump", "--no-pull-requests", "headonly", "version-latest" }
        .to output(/Formula is HEAD-only.*Cask uses `version :latest`/m).to_stdout
        .and not_to_output.to_stderr
        .and be_a_success
    end
  end

  it "gives an error for `--tap` with official taps" do
    allow(Utils::GemSetup).to receive(:install_bundler_gems!)

    expect { described_class.new(["--tap", "Homebrew/core"]).run }
      .to raise_error(UsageError, /`--tap` requires `--auto` for official taps/)
  end

  describe "::skip_ineligible_package!" do
    it "prints a message for disabled formulae" do
      expect { expect(bump.skip_ineligible_package!(f_disabled)).to be(true) }
        .to output(/Formula is disabled so not accepting updates\./).to_stdout
        .and not_to_output.to_stderr
    end

    it "prints a message for HEAD-only formulae" do
      expect { expect(bump.skip_ineligible_package!(f_head_only)).to be(true) }
        .to output(/Formula is HEAD-only so not accepting updates\./).to_stdout
        .and not_to_output.to_stderr
    end

    it "prints a message for disabled casks" do
      expect { expect(bump.skip_ineligible_package!(c_disabled)).to be(true) }
        .to output(/Cask is disabled so not accepting updates\./).to_stdout
        .and not_to_output.to_stderr
    end

    it "prints a message for casks using `version :latest`" do
      expect { expect(bump.skip_ineligible_package!(c_latest)).to be(true) }
        .to output(/Cask uses `version :latest` so `brew bump` cannot check it\./).to_stdout
        .and not_to_output.to_stderr
    end

    it "prints a message for autobumped packages" do
      allow(f_basic).to receive(:tap).and_return(instance_double(Tap, allow_bump?: false))

      expect { expect(bump.skip_ineligible_package!(f_basic)).to be(true) }
        .to output(/Formula is autobumped so will have bump PRs opened by BrewTestBot/).to_stdout
        .and not_to_output.to_stderr
    end

    it "doesn't overwrite an existing skip message with the autobump message" do
      allow(f_disabled).to receive(:tap).and_return(instance_double(Tap, allow_bump?: false))

      expect { expect(bump.skip_ineligible_package!(f_disabled)).to be(true) }
        .to output(/Formula is disabled so not accepting updates\./).to_stdout
        .and not_to_output.to_stderr
    end

    it "returns false for an eligible package" do
      allow(f_basic).to receive(:tap).and_return(instance_double(Tap, allow_bump?: true))

      expect { expect(bump.skip_ineligible_package!(f_basic)).to be(false) }
        .to not_to_output.to_stdout
        .and not_to_output.to_stderr
    end

    it "returns false for a formula disabled only on the current arch" do
      expect { expect(bump.skip_ineligible_package!(f_partially_disabled_arch)).to be(false) }
        .to not_to_output.to_stdout
        .and not_to_output.to_stderr
    end

    it "returns false for a formula disabled only on the current os" do
      expect { expect(bump.skip_ineligible_package!(f_partially_disabled_os)).to be(false) }
        .to not_to_output.to_stdout
        .and not_to_output.to_stderr
    end

    it "returns false for a cask disabled only on the current arch" do
      expect { expect(bump.skip_ineligible_package!(c_partially_disabled_arch)).to be(false) }
        .to not_to_output.to_stdout
        .and not_to_output.to_stderr
    end

    it "returns false for a cask disabled only on the current os" do
      expect { expect(bump.skip_ineligible_package!(c_partially_disabled_os)).to be(false) }
        .to not_to_output.to_stdout
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
      expect(bump.compare_versions(general_version, general_version, f_basic)).to eq({
        multiple_versions:   { current: false, new: false },
        newer_than_upstream: { general: false },
      })
      expect(bump.compare_versions(general_version, general_version, c_basic)).to eq({
        multiple_versions:   { current: false, new: false },
        newer_than_upstream: { general: false },
      })
      expect(bump.compare_versions(arm_intel_version, arm_intel_version, c_basic)).to eq({
        multiple_versions:   { current: true, new: true },
        newer_than_upstream: { arm: false, intel: false },
      })

      # Compare current versions to new version when the current version differs
      # by arch but the new version does not
      expect(bump.compare_versions(arm_intel_version, general_version, c_basic)).to eq({
        multiple_versions:   { current: true, new: false },
        newer_than_upstream: { arm: false, intel: false },
      })

      # Compare current version to the highest new version when the
      # current version does not differ by arch but the new version does
      expect(bump.compare_versions(general_version, arm_intel_version, c_basic)).to eq({
        multiple_versions:   { current: false, new: true },
        newer_than_upstream: { general: false },
      })
      expect(bump.compare_versions(general_version, arm_intel_version_higher, c_basic)).to eq({
        multiple_versions:   { current: false, new: true },
        newer_than_upstream: { general: false },
      })
      expect(bump.compare_versions(general_version, arm_version_intel_skipped, c_basic)).to eq({
        multiple_versions:   { current: false, new: true },
        newer_than_upstream: { general: false },
      })

      # Default to `false` when the new version is a message rather than a
      # version
      expect(bump.compare_versions(general_version, skipped, c_basic)).to eq({
        multiple_versions:   { current: false, new: false },
        newer_than_upstream: { general: false },
      })
      expect(bump.compare_versions(general_version, unable_to_get_versions, c_basic)).to eq({
        multiple_versions:   { current: false, new: false },
        newer_than_upstream: { general: false },
      })
      expect(bump.compare_versions(general_version, unable_to_get_throttled_versions, c_basic)).to eq({
        multiple_versions:   { current: false, new: false },
        newer_than_upstream: { general: false },
      })
    end
  end

  describe "::retrieve_and_display_info_and_open_pr" do
    subject(:bump) { described_class.new(["--open-pr", "test"]) }

    before do
      allow(bump).to receive(:retrieve_pull_requests)
      allow(GitHub).to receive(:too_many_open_prs?).and_return(false)
    end

    it "passes arch-specific version arguments when a cask moves from one version to arch-specific versions" do
      version_info = Homebrew::DevCmd::Bump::VersionBumpInfo.new(
        type:                    :cask,
        deprecated:              { general: false },
        multiple_versions:       { current: false, new: true },
        version_name:            "cask version:   ",
        current_version:         Homebrew::BumpVersionParser.new(general: Version.new("1.2.3")),
        new_version:             Homebrew::BumpVersionParser.new(
          arm:   Version.new("1.2.5"),
          intel: Version.new("1.2.4"),
        ),
        repology_latest:         "not found",
        newer_than_upstream:     { general: false },
        duplicate_pull_requests: nil,
        open_bump_pull_requests: nil,
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

      bump.retrieve_and_display_info_and_open_pr(c_basic, "basic-cask", [], ambiguous_cask: false)
    end

    it "passes arch-specific version arguments when an arch-specific cask moves to one version" do
      version_info = Homebrew::DevCmd::Bump::VersionBumpInfo.new(
        type:                    :cask,
        deprecated:              { arm: false, intel: false },
        multiple_versions:       { current: true, new: false },
        version_name:            "cask version:   ",
        current_version:         Homebrew::BumpVersionParser.new(
          arm:   Version.new("1.2.3"),
          intel: Version.new("1.2.2"),
        ),
        new_version:             Homebrew::BumpVersionParser.new(general: Version.new("1.2.4")),
        repology_latest:         "not found",
        newer_than_upstream:     { arm: false, intel: false },
        duplicate_pull_requests: nil,
        open_bump_pull_requests: nil,
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

      bump.retrieve_and_display_info_and_open_pr(c_basic, "basic-cask", [], ambiguous_cask: false)
    end

    it "notes when a newer upstream version was skipped due to release cooldown" do
      version_info = Homebrew::DevCmd::Bump::VersionBumpInfo.new(
        type:                      :formula,
        deprecated:                { general: false },
        multiple_versions:         { current: false, new: false },
        version_name:              "formula version:",
        current_version:           Homebrew::BumpVersionParser.new(general: Version.new("1.2.3")),
        new_version:               Homebrew::BumpVersionParser.new(general: Version.new("1.2.3")),
        repology_latest:           "not found",
        newer_than_upstream:       { general: false },
        cooldown_skipped_versions: { general: Version.new("1.2.4") },
        duplicate_pull_requests:   nil,
        open_bump_pull_requests:   nil,
      )
      allow(bump).to receive(:retrieve_versions_by_arch).and_return(version_info)

      expect { bump.retrieve_and_display_info_and_open_pr(f_basic, "basic_formula", [], ambiguous_cask: false) }
        .to output(<<~EOS).to_stdout
          ==> basic_formula has a new version in release cooldown
          Current formula version:  1.2.3
          Latest livecheck version: 1.2.4 (released less than 1 day ago)
          Bump-ready version:       1.2.3
        EOS
    end
  end

  describe "::retrieve_versions_by_arch" do
    before do
      allow(bump).to receive(:retrieve_pull_requests)
    end

    let(:c_arm_only) do
      Cask::CaskLoader.load(+<<-RUBY)
        cask "arm_only_cask" do
          arch arm: "arm64", intel: "x64"

          version "1.2.3"
          sha256 :no_check

          url "https://brew.sh/test-\#{arch}.dmg"
          name "Arm Only Cask"
          desc "Arm only cask"
          homepage "https://brew.sh"

          depends_on arch: :arm64
        end
      RUBY
    end
    let(:c_intel_only) do
      Cask::CaskLoader.load(+<<-RUBY)
        cask "intel_only_cask" do
          arch arm: "arm64", intel: "x64"

          version "1.2.3"
          sha256 :no_check

          url "https://brew.sh/test-\#{arch}.dmg"
          name "Intel Only Cask"
          desc "Intel only cask"
          homepage "https://brew.sh"

          depends_on arch: :x86_64
        end
      RUBY
    end
    let(:c_multi_arch) do
      Cask::CaskLoader.load(+<<-RUBY)
        cask "multi_arch_cask" do
          arch arm: "arm64", intel: "x64"

          version "1.2.3"
          sha256 :no_check

          url "https://brew.sh/test-\#{arch}.dmg"
          name "Multi Arch Cask"
          desc "Multi arch cask"
          homepage "https://brew.sh"
        end
      RUBY
    end

    it "simulates only arm and consolidates to a general version when `depends_on arch:` restricts to arm-only" do
      allow(c_arm_only).to receive(:sourcefile_path).and_return(Pathname("arm_only_cask.rb"))
      allow(Cask::CaskLoader).to receive(:load).and_return(c_arm_only)
      expect(bump).to receive(:livecheck_result).once.and_return([Version.new("1.2.4"), nil])

      version_info = bump.retrieve_versions_by_arch(
        formula_or_cask: c_arm_only, repositories: [], name: "arm-only-cask",
      )
      expect(version_info.new_version).to eq(Homebrew::BumpVersionParser.new(general: Version.new("1.2.4")))
    end

    it "simulates only intel and consolidates to a general version when `depends_on arch:` restricts to intel-only" do
      allow(c_intel_only).to receive(:sourcefile_path).and_return(Pathname("intel_only_cask.rb"))
      allow(Cask::CaskLoader).to receive(:load).and_return(c_intel_only)
      expect(bump).to receive(:livecheck_result).once.and_return([Version.new("1.2.4"), nil])

      version_info = bump.retrieve_versions_by_arch(
        formula_or_cask: c_intel_only, repositories: [], name: "intel-only-cask",
      )
      expect(version_info.new_version).to eq(Homebrew::BumpVersionParser.new(general: Version.new("1.2.4")))
    end

    it "records the upstream version skipped due to release cooldown" do
      expect(bump).to receive(:livecheck_result).once.and_return([Version.new("1.2.3"), Version.new("1.2.4")])

      version_info = bump.retrieve_versions_by_arch(
        formula_or_cask: f_basic, repositories: [], name: "basic_formula",
      )
      expect(version_info.cooldown_skipped_versions).to eq({ general: Version.new("1.2.4") })
    end

    it "records cooldown-skipped versions per architecture" do
      allow(c_multi_arch).to receive(:sourcefile_path).and_return(Pathname("multi_arch_cask.rb"))
      allow(Cask::CaskLoader).to receive(:load).and_return(c_multi_arch)
      expect(bump).to receive(:livecheck_result).twice.and_return(
        [Version.new("1.2.3"), Version.new("1.2.4")],
        [Version.new("1.2.3"), Version.new("1.2.5")],
      )

      version_info = bump.retrieve_versions_by_arch(
        formula_or_cask: c_multi_arch, repositories: [], name: "multi-arch-cask",
      )
      expect(version_info.cooldown_skipped_versions).to eq({ arm:   Version.new("1.2.5"),
                                                             intel: Version.new("1.2.4") })
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
      expect(bump.message?(version)).to be(false)
      expect(bump.message?(nil)).to be(false)
    end

    it "returns false when `Cask::DSL::Version` or string is not a message" do
      expect(bump.message?(cask_version)).to be(false)
      expect(bump.message?("Not a message string")).to be(false)
    end

    it "returns true when `Cask::DSL::Version` or string is a message" do
      message_strings.each do |message_string|
        expect(bump.message?(Cask::DSL::Version.new(message_string))).to be(true)
        expect(bump.message?(message_string)).to be(true)
      end
    end
  end

  describe "::version_args_for_bump" do
    let(:current_general) { Homebrew::BumpVersionParser.new(general: "1.2.5") }
    let(:new_split) do
      Homebrew::BumpVersionParser.new(
        arm:   "1.2.6",
        intel: "1.2.5",
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
        bump.version_args_for_bump(current_version:   current_general,
                                   new_version:       new_split,
                                   multiple_versions: { current: false, new: true },
                                   name:              "foo"),
      ).to eq(["--version-arm=1.2.6"])
    end

    it "emits arch arguments for both architectures when split cask versions merge" do
      expect(
        bump.version_args_for_bump(current_version:   current_split,
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
        bump.version_args_for_bump(current_version:   current_split,
                                   new_version:       new_split,
                                   multiple_versions: { current: true, new: true },
                                   name:              "foo"),
      ).to eq(["--version-arm=1.2.4"])
    end

    it "keeps existing general version routing" do
      expect(
        bump.version_args_for_bump(current_version:   current_general,
                                   new_version:       new_general,
                                   multiple_versions: { current: false, new: false },
                                   name:              "foo"),
      ).to eq(["--version=1.2.4"])
    end

    it "ignores message versions in arch-specific routing" do
      new_split = Homebrew::BumpVersionParser.new(
        arm:   "1.2.6",
        intel: "skipped",
      )

      expect(
        bump.version_args_for_bump(current_version:   current_general,
                                   new_version:       new_split,
                                   multiple_versions: { current: false, new: true },
                                   name:              "foo"),
      ).to eq(["--version-arm=1.2.6"])
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

      expect(bump.version_with_cooldown(version_info, Version.new("1.2.2"))).to eq(Version.new("1.2.3"))
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

      expect(bump.version_with_cooldown(version_info, Version.new("1.2.2"))).to eq(Version.new("1.2.3"))
    end

    it "uses semver precedence for npm prerelease versions" do
      version_info = {
        latest: "1.2.4",
        meta:   {
          strategy: "Npm",
          url:      {
            strategy: "https://registry.npmjs.org/example-package/latest",
          },
        },
      }
      content = <<~JSON
        {
          "time": {
            "created": "2026-02-01T00:00:00.000Z",
            "modified": "2026-04-04T00:00:00.000Z",
            "1.2.3-next.1": "2026-02-01T00:00:00.000Z",
            "1.2.4-next.2": "2026-03-01T00:00:00.000Z",
            "1.2.4": "2026-04-04T00:00:00.000Z"
          }
        }
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
          "https://registry.npmjs.org/example-package",
          connect_timeout: 15,
          max_time:        55,
          retries:         0,
          timeout:         60,
        )
        .and_return([content, "", instance_double(Process::Status, success?: true)])

      expect(bump.version_with_cooldown(version_info, Version.new("1.2.3-next.1")))
        .to eq(Version.new("1.2.4-next.2"))
    end
  end

  describe "::retrieve_pull_requests" do
    let(:name) { "basic_formula" }
    let(:tap_name) { "homebrew/tap" }
    let(:version) { "1.2.3" }
    let(:title) { "#{name} #{version}" }
    let(:pull_url) { "https://github.com/Homebrew/homebrew-tap/pull" }
    let(:pull_requests) { [] }

    before do
      allow(f_basic).to receive(:tap).and_return(Tap.fetch(tap_name))
      allow(GitHub).to receive(:fetch_pull_requests).and_return(pull_requests)
      add_pull_request(title, 100)
    end

    def add_pull_request(title, number)
      pull_requests.append({
        "number"   => number,
        "title"    => title,
        "state"    => "open",
        "html_url" => "#{pull_url}/#{number}",
      })
    end

    it "outputs all pull requests API returned when given a version" do
      title_2 = "#{name}: update to #{version}"
      add_pull_request(title_2, 101)
      expect(bump.retrieve_pull_requests(f_basic, name, version:)).to eq(
        "#{title} (#{pull_url}/100), #{title_2} (#{pull_url}/101)",
      )
    end

    it "filters pull requests when not given a version" do
      add_pull_request("#{name}: fix an issue with formula", 101)
      add_pull_request("some other PR with #{name} #{version}", 102)
      expect(bump.retrieve_pull_requests(f_basic, name)).to eq("#{title} (#{pull_url}/100)")
    end
  end
end
