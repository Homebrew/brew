# typed: true
# frozen_string_literal: true

require "cask/cask_loader"
require "cask/ci/runner_matrix"

RSpec.describe Cask::CI::RunnerMatrix do
  let(:c_on_system_depends_on_mixed) do
    Cask::Cask.new("test-on-system-depends-on-mixed") do
      os macos: "darwin", linux: "linux"

      version "0.0.1,2"

      url "https://brew.sh/test-0.0.1.dmg"
      name "Test"
      desc "Test cask"
      homepage "https://brew.sh"

      on_macos do
        depends_on arch: :x86_64
      end

      on_linux do
        depends_on arch: :arm64
      end
    end
  end
  let(:c_on_macos_depends_on_intel) do
    Cask::Cask.new("test-on-macos-depends-on-intel") do
      os macos: "darwin", linux: "linux"

      version "0.0.1,2"

      url "https://brew.sh/test-0.0.1.dmg"
      name "Test"
      desc "Test cask"
      homepage "https://brew.sh"

      on_macos do
        depends_on arch: :x86_64
      end
    end
  end
  let(:c_on_linux_depends_on_intel) do
    Cask::Cask.new("test-on-linux-depends-on-intel") do
      os macos: "darwin", linux: "linux"

      version "0.0.1,2"

      url "https://brew.sh/test-0.0.1.dmg"
      name "Test"
      desc "Test cask"
      homepage "https://brew.sh"

      on_linux do
        depends_on arch: :x86_64
      end
    end
  end
  let(:c_on_system_depends_on_intel) do
    Cask::Cask.new("test-on-system-depends-on-intel") do
      os macos: "darwin", linux: "linux"

      version "0.0.1,2"

      url "https://brew.sh/test-0.0.1.dmg"
      name "Test"
      desc "Test cask"
      homepage "https://brew.sh"

      depends_on arch: :x86_64
    end
  end
  let(:c_on_system) do
    Cask::Cask.new("test-on-system") do
      os macos: "darwin", linux: "linux"

      version "0.0.1,2"

      url "https://brew.sh/test-0.0.1.dmg"
      name "Test"
      desc "Test cask"
      homepage "https://brew.sh"
    end
  end
  let(:c_on_macos_depends_on_arm) do
    Cask::Cask.new("test-on-macos-depends-on-arm") do
      os macos: "darwin", linux: "linux"

      version "0.0.1,2"

      url "https://brew.sh/test-0.0.1.dmg"
      name "Test"
      desc "Test cask"
      homepage "https://brew.sh"

      on_macos do
        depends_on arch: :arm64
      end
    end
  end
  let(:c_depends_macos_on_intel) do
    Cask::Cask.new("test-depends-on-intel") do
      version "0.0.1,2"

      url "https://brew.sh/test-0.0.1.dmg"
      name "Test"
      desc "Test cask"
      homepage "https://brew.sh"

      depends_on :macos
      depends_on arch: :x86_64

      app "Test.app"
    end
  end
  let(:c_app) do
    Cask::Cask.new("test-app") do
      version "0.0.1,2"

      url "https://brew.sh/test-0.0.1.dmg"
      name "Test"
      desc "Test cask"
      homepage "https://brew.sh"

      depends_on :macos

      app "Test.app"
    end
  end
  let(:c_minimum_macos) do
    Cask::Cask.new("test-minimum-macos") do
      version "0.0.1,2"

      url "https://brew.sh/test-0.0.1.dmg"
      name "Test"
      desc "Test cask"
      homepage "https://brew.sh"

      depends_on macos: :tahoe

      app "Test.app"
    end
  end
  let(:c_maximum_macos) do
    Cask::Cask.new("test-maximum-macos") do
      version "0.0.1,2"

      url "https://brew.sh/test-0.0.1.dmg"
      name "Test"
      desc "Test cask"
      homepage "https://brew.sh"

      depends_on maximum_macos: :sequoia

      app "Test.app"
    end
  end
  let(:c_macos_version_variations) do
    Cask::Cask.new("test-macos-version-variations") do
      on_sequoia :or_older do
        version "0.0.1"
      end
      on_tahoe :or_newer do
        version "0.0.2"
      end

      url "https://brew.sh/test.dmg"
      name "Test"
      desc "Test cask"
      homepage "https://brew.sh"

      depends_on :macos

      app "Test.app"
    end
  end
  let(:c_sequoia_only_url) do
    Cask::Cask.new("test-sequoia-only-url") do
      on_sequoia :or_older do
        version "0.0.1"
      end
      on_tahoe :or_newer do
        version "0.0.2"
      end

      url "https://brew.sh/test-#{version}.dmg"
      name "Test"
      desc "Test cask"
      homepage "https://brew.sh"

      depends_on :macos

      app "Test.app"
    end
  end
  let(:c_maximum_macos_below_all_runners) do
    Cask::Cask.new("test-maximum-macos-below-all-runners") do
      version "0.0.1,2"

      url "https://brew.sh/test-0.0.1.dmg"
      name "Test"
      desc "Test cask"
      homepage "https://brew.sh"

      depends_on maximum_macos: :ventura

      app "Test.app"
    end
  end
  let(:c_minimum_and_maximum_macos) do
    Cask::Cask.new("test-minimum-and-maximum-macos") do
      version "0.0.1,2"

      url "https://brew.sh/test-0.0.1.dmg"
      name "Test"
      desc "Test cask"
      homepage "https://brew.sh"

      depends_on macos: :sequoia
      depends_on maximum_macos: :tahoe

      app "Test.app"
    end
  end
  let(:c_linux) do
    Cask::Cask.new("test-linux") do
      version "0.0.1,2"

      url "https://brew.sh/test-0.0.1.tar.gz"
      name "Test"
      desc "Test cask"
      homepage "https://brew.sh"

      depends_on :linux

      binary "test"
    end
  end
  let(:c_app_only_macos) do
    Cask::Cask.new("test-on-macos-guarded-stanza") do
      os macos: "darwin", linux: "linux"
      version "0.0.1,2"

      url "https://brew.sh/test-0.0.1.dmg"
      name "Test"
      desc "Test cask"
      homepage "https://brew.sh"

      on_macos do
        app "Test.app"
      end
    end
  end
  let(:c_disabled_on_macos) do
    Cask::Cask.new("test-disabled-on-macos") do
      os macos: "darwin", linux: "linux"
      version "0.0.1,2"

      url "https://brew.sh/test-0.0.1.dmg"
      name "Test"
      desc "Test cask"
      homepage "https://brew.sh"

      on_macos do
        disable! date: "2020-01-01", because: :fails_gatekeeper_check
      end
    end
  end
  let(:c_disabled) do
    Cask::Cask.new("test-disabled") do
      version "0.0.1,2"

      url "https://brew.sh/test-0.0.1.dmg"
      name "Test"
      desc "Test cask"
      homepage "https://brew.sh"

      disable! date: "2020-01-01", because: :discontinued
    end
  end
  let(:c) do
    Cask::Cask.new("test-font") do
      version "0.0.1,2"

      url "https://brew.sh/test-0.0.1.dmg"
      name "Test"
      desc "Test cask"
      homepage "https://brew.sh"

      font "Test.ttf"
    end
  end

  describe "cask job audit arguments" do
    subject(:audit_args_by_runner) { jobs.to_h { |job| [job.fetch(:runner), job.fetch(:audit_args)] } }

    let(:jobs) do
      described_class.generate(CoreCaskTap.instance, ["test"], added_casks: [], labels:, skip_install: false,
                               new_cask: false)
    end
    let(:labels) { [] }
    let(:cask) { c_macos_version_variations }

    before do
      allow(Cask::CaskLoader).to receive(:from_tap_path).and_return(cask)
    end

    context "when a cask varies across macOS versions" do
      it "skips the signing audit only on macOS 15" do
        expect(audit_args_by_runner).to eq(
          "macos-15" => ["--online", "--except", "signing"],
          "macos-26" => ["--online"],
          "xcode-27" => ["--online"],
        )
      end

      context "with labels skipping install and homepage audits" do
        let(:labels) { %w[ci-skip-install ci-skip-homepage] }

        it "merges the label's exceptions on every runner" do
          expect(audit_args_by_runner).to eq(
            "macos-15" => ["--online", "--except", "homepage_https_availability,homepage_domain_age,signing"],
            "macos-26" => ["--online", "--except", "homepage_https_availability,homepage_domain_age"],
            "xcode-27" => ["--online", "--except", "homepage_https_availability,homepage_domain_age"],
          )
          sequoia = jobs.find { |row| row.fetch(:runner) == "macos-15" } || raise("missing macos-15 runner")
          expect(sequoia.fetch(:test_bot_args)).to contain_exactly(
            "--only-casks", "--skip-install", "--except=homepage_https_availability,homepage_domain_age,signing"
          )
        end
      end
    end

    it "scopes bare added tokens to the default tap" do
      jobs = described_class.generate(CoreCaskTap.instance, %w[test other/tap/test another/tap/test],
                                      added_casks: %w[test another/tap/test], labels: [], skip_install: false,
                                      new_cask: false)

      expect(jobs.to_h { |job| [job.fetch(:tap), Array(job.fetch(:audit_args)).include?("--new")] })
        .to eq("homebrew/cask" => true, "other/tap" => false, "another/tap" => true)
      expect(jobs.map { |job| job.values_at(:testing_casks, :added_casks) }.uniq)
        .to eq([%w[test test], ["other/tap/test", ""], %w[another/tap/test another/tap/test]])
    end

    context "when only macOS 15 downloads a cask's URL" do
      let(:cask) { c_sequoia_only_url }

      it "keeps the signing audit" do
        expect(audit_args_by_runner).to eq(
          "macos-15" => ["--online"],
          "macos-26" => ["--online"],
          "xcode-27" => ["--online"],
        )
      end
    end

    context "when macOS 15 is the only macOS runner for a cask" do
      let(:cask) { c_maximum_macos }

      it "keeps the signing audit" do
        expect(audit_args_by_runner).to eq("macos-15" => ["--online"])
      end
    end
  end

  describe "::filter_runners" do
    let(:arm_linux_runner) { OS::LINUX_CI_ARM_RUNNER }

    context "when cask does not have on_system blocks/calls or `depends_on arch`" do
      it "returns an array including everything" do
        expect(described_class.filter_runners(c))
          .to eq({
            { arch: :arm, name: "macos-15", symbol: :sequoia }      => 0.0,
            { arch: :arm, name: "macos-26", symbol: :tahoe }        => 0.0,
            { arch: :arm, name: "xcode-27", symbol: :golden_gate }  => 1.0,
            { arch: :arm, name: arm_linux_runner, symbol: :linux }  => 1.0,
            { arch: :intel, name: "ubuntu-latest", symbol: :linux } => 1.0,
          })

        expect(described_class.filter_runners(c_app_only_macos))
          .to eq({
            { arch: :arm, name: "macos-15", symbol: :sequoia }      => 0.0,
            { arch: :arm, name: "macos-26", symbol: :tahoe }        => 0.0,
            { arch: :arm, name: "xcode-27", symbol: :golden_gate }  => 1.0,
            { arch: :arm, name: arm_linux_runner, symbol: :linux }  => 1.0,
            { arch: :intel, name: "ubuntu-latest", symbol: :linux } => 1.0,
          })
      end
    end

    context "when cask is disabled" do
      it "excludes the runners the cask is disabled on" do
        expect(described_class.filter_runners(c_disabled_on_macos))
          .to eq({
            { arch: :arm, name: arm_linux_runner, symbol: :linux }  => 1.0,
            { arch: :intel, name: "ubuntu-latest", symbol: :linux } => 1.0,
          })
      end

      it "excludes every runner for a cask disabled everywhere" do
        expect(described_class.filter_runners(c_disabled)).to eq({})
      end
    end

    context "when cask does not have on_system blocks/calls but has macOS specific stanza" do
      it "returns an array including all macOS" do
        expect(described_class.filter_runners(c_app))
          .to eq({
            { arch: :arm, name: "macos-15", symbol: :sequoia }     => 0.0,
            { arch: :arm, name: "macos-26", symbol: :tahoe }       => 0.0,
            { arch: :arm, name: "xcode-27", symbol: :golden_gate } => 1.0,
          })
      end
    end

    context "when cask has a macOS version requirement" do
      it "filters macOS runners by the minimum and maximum macOS requirements" do
        expect(described_class.filter_runners(c_minimum_macos))
          .to eq({
            { arch: :arm, name: "macos-26", symbol: :tahoe }       => 0.0,
            { arch: :arm, name: "xcode-27", symbol: :golden_gate } => 1.0,
          })

        expect(described_class.filter_runners(c_maximum_macos))
          .to eq({ { arch: :arm, name: "macos-15", symbol: :sequoia } => 0.0 })

        expect(described_class.filter_runners(c_minimum_and_maximum_macos))
          .to eq({
            { arch: :arm, name: "macos-15", symbol: :sequoia } => 0.0,
            { arch: :arm, name: "macos-26", symbol: :tahoe }   => 0.0,
          })

        # A requirement excluding all runners must skip macOS, not test them all.
        expect(described_class.filter_runners(c_maximum_macos_below_all_runners)).to eq({})
      end
    end

    context "when cask only supports Linux" do
      it "returns an array including all Linux" do
        expect(described_class.filter_runners(c_linux))
          .to eq({
            { arch: :arm, name: arm_linux_runner, symbol: :linux }  => 1.0,
            { arch: :intel, name: "ubuntu-latest", symbol: :linux } => 1.0,
          })
      end
    end

    context "when cask does not have on_system blocks/calls but has `depends_on arch`" do
      it "returns no runners for an Intel-only macOS cask" do
        expect(described_class.filter_runners(c_depends_macos_on_intel)).to eq({})
      end
    end

    context "when cask has on_system blocks/calls but does not have `depends_on arch`" do
      it "returns an array with combinations of OS and architectures" do
        expect(described_class.filter_runners(c_on_system))
          .to eq({
            { arch: :arm, name: "macos-15", symbol: :sequoia }      => 0.0,
            { arch: :arm, name: "macos-26", symbol: :tahoe }        => 0.0,
            { arch: :arm, name: "xcode-27", symbol: :golden_gate }  => 1.0,
            { arch: :arm, name: arm_linux_runner, symbol: :linux }  => 1.0,
            { arch: :intel, name: "ubuntu-latest", symbol: :linux } => 1.0,
          })
      end
    end

    context "when cask has on_system blocks/calls and `depends_on arch`" do
      it "returns an array with combinations of OS and `depends_on arch` value" do
        expect(described_class.filter_runners(c_on_system_depends_on_intel))
          .to eq({ { arch: :intel, name: "ubuntu-latest", symbol: :linux } => 1.0 })

        expect(described_class.filter_runners(c_on_linux_depends_on_intel))
          .to eq({
            { arch: :arm, name: "macos-15", symbol: :sequoia }      => 0.0,
            { arch: :arm, name: "macos-26", symbol: :tahoe }        => 0.0,
            { arch: :arm, name: "xcode-27", symbol: :golden_gate }  => 1.0,
            { arch: :intel, name: "ubuntu-latest", symbol: :linux } => 1.0,
          })

        expect(described_class.filter_runners(c_on_macos_depends_on_intel))
          .to eq({
            { arch: :intel, name: "ubuntu-latest", symbol: :linux } => 1.0,
            { arch: :arm, name: arm_linux_runner, symbol: :linux }  => 1.0,
          })

        expect(described_class.filter_runners(c_on_macos_depends_on_arm))
          .to eq({
            { arch: :arm, name: "macos-15", symbol: :sequoia }      => 0.0,
            { arch: :arm, name: "macos-26", symbol: :tahoe }        => 0.0,
            { arch: :arm, name: "xcode-27", symbol: :golden_gate }  => 1.0,
            { arch: :arm, name: arm_linux_runner, symbol: :linux }  => 1.0,
            { arch: :intel, name: "ubuntu-latest", symbol: :linux } => 1.0,
          })

        expect(described_class.filter_runners(c_on_system_depends_on_mixed))
          .to eq({ { arch: :arm, name: arm_linux_runner, symbol: :linux } => 1.0 })
      end
    end
  end

  describe "::runners" do
    let(:arm_linux_runner) { OS::LINUX_CI_ARM_RUNNER }

    it "selects one macOS runner and every Linux runner" do
      allow(described_class).to receive(:random_runner) { |runners| runners.keys.first }

      expect(described_class.runners(cask: c).map { |runner| runner.fetch(:name) })
        .to contain_exactly("macos-15", arm_linux_runner, "ubuntu-latest")
    end

    it "selects only Linux runners for an Intel-only macOS cask" do
      expect(described_class.runners(cask: c_on_macos_depends_on_intel).map { |runner| runner.fetch(:name) })
        .to contain_exactly(arm_linux_runner, "ubuntu-latest")
    end
  end
end
