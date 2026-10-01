# typed: true
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/generate-cask-ci-matrix"

RSpec.describe Homebrew::DevCmd::GenerateCaskCiMatrix do
  subject(:generate_matrix) { described_class.new(["test"]) }

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
  let(:newest_macos) { MacOSVersion.new(HOMEBREW_MACOS_NEWEST_SUPPORTED).to_sym }

  it_behaves_like "parseable arguments"

  it "generates current and stable tap syntax jobs" do
    ENV["GITHUB_REPOSITORY"] = "Homebrew/homebrew-cask"
    ENV.delete("GITHUB_OUTPUT")
    command = described_class.new(["--syntax-only"])
    allow(command).to receive(:random_runner).and_return({ name: "macos-26" })
    stdout = StringIO.new
    allow(command).to receive(:puts) { |output| stdout.puts(output) }

    command.run

    expect(JSON.parse(stdout.string)).to eq(
      [
        {
          "name"   => "tap_syntax (macos-26)",
          "tap"    => "homebrew/cask",
          "runner" => "macos-26",
          "stable" => false,
        },
        {
          "name"       => "tap_syntax (stable) (macos-26)",
          "tap"        => "homebrew/cask",
          "runner"     => "macos-26",
          "stable"     => true,
          "skip_audit" => true,
        },
      ],
    )
  end

  it "rejects a matrix exceeding GitHub's job limit" do
    ENV["GITHUB_REPOSITORY"] = "Homebrew/homebrew-cask"
    ENV.delete("GITHUB_OUTPUT")
    command = described_class.new(["--cask", "test"])
    allow(command).to receive_messages(random_runner:   { name: "macos-26" },
                                       generate_matrix: Array.new(
                                         Homebrew::DevCmd::GenerateCaskCiMatrix::MAX_JOBS - 1, {}
                                       ))

    expect { command.run }
      .to output("Error: Maximum job matrix size exceeded: 257/256\n").to_stderr
      .and raise_error(SystemExit)
  end

  it "generates a cask matrix in a clean process", :cask, :integration_test, :no_api do
    CoreCaskTap.instance.path.cd do
      system "git", "init", "--quiet"
      system "git", "-c", "user.name=Homebrew Tests", "-c", "user.email=tests@brew.sh",
             "commit", "--quiet", "--allow-empty", "-m", "initial"
      system "git", "branch", "origin"

      # Run without the Sorbet runtime so this exercises the same `require` graph as
      # a real `brew generate-cask-ci-matrix`, which loads fewer files.
      brew_env = {
        "CI"                        => "1",
        "GITHUB_OUTPUT"             => nil,
        "GITHUB_REPOSITORY"         => "Homebrew/homebrew-cask",
        "HOMEBREW_SORBET_RECURSIVE" => nil,
        "HOMEBREW_SORBET_RUNTIME"   => nil,
      }

      expect do
        expect do
          brew "generate-cask-ci-matrix", "--cask", "local-caffeine", brew_env
        end.to be_a_success
      end.to output(/"token": "local-caffeine"/).to_stdout
    end
  end

  describe "::filter_runners" do
    let(:arm_linux_runner) { OS::LINUX_CI_ARM_RUNNER }
    # We simulate a macOS version older than the newest, as the method will use
    # the host macOS version instead of the default (the newest macOS version).
    let(:older_macos) { :big_sur }

    context "when cask does not have on_system blocks/calls or `depends_on arch`" do
      it "returns an array including everything" do
        expect(generate_matrix.filter_runners(c))
          .to eq({
            { arch: :arm, name: "macos-15", symbol: :sequoia }      => 0.0,
            { arch: :arm, name: "macos-26", symbol: :tahoe }        => 1.0,
            { arch: :arm, name: "xcode-27", symbol: :golden_gate }  => 0.0,
            { arch: :arm, name: arm_linux_runner, symbol: :linux }  => 1.0,
            { arch: :intel, name: "ubuntu-latest", symbol: :linux } => 1.0,
          })

        expect(generate_matrix.filter_runners(c_app_only_macos))
          .to eq({
            { arch: :arm, name: "macos-15", symbol: :sequoia }      => 0.0,
            { arch: :arm, name: "macos-26", symbol: :tahoe }        => 1.0,
            { arch: :arm, name: "xcode-27", symbol: :golden_gate }  => 0.0,
            { arch: :arm, name: arm_linux_runner, symbol: :linux }  => 1.0,
            { arch: :intel, name: "ubuntu-latest", symbol: :linux } => 1.0,
          })
      end
    end

    context "when cask is disabled" do
      it "excludes the runners the cask is disabled on" do
        expect(generate_matrix.filter_runners(c_disabled_on_macos))
          .to eq({
            { arch: :arm, name: arm_linux_runner, symbol: :linux }  => 1.0,
            { arch: :intel, name: "ubuntu-latest", symbol: :linux } => 1.0,
          })
      end

      it "excludes every runner for a cask disabled everywhere" do
        expect(generate_matrix.filter_runners(c_disabled)).to eq({})
      end
    end

    context "when cask does not have on_system blocks/calls but has macOS specific stanza" do
      it "returns an array including all macOS" do
        expect(generate_matrix.filter_runners(c_app))
          .to eq({
            { arch: :arm, name: "macos-15", symbol: :sequoia }     => 0.0,
            { arch: :arm, name: "macos-26", symbol: :tahoe }       => 1.0,
            { arch: :arm, name: "xcode-27", symbol: :golden_gate } => 0.0,
          })
      end
    end

    context "when cask has a macOS version requirement" do
      it "filters macOS runners by the minimum and maximum macOS requirements" do
        expect(generate_matrix.filter_runners(c_minimum_macos))
          .to eq({
            { arch: :arm, name: "macos-26", symbol: :tahoe }       => 1.0,
            { arch: :arm, name: "xcode-27", symbol: :golden_gate } => 0.0,
          })

        expect(generate_matrix.filter_runners(c_maximum_macos))
          .to eq({ { arch: :arm, name: "macos-15", symbol: :sequoia } => 0.0 })

        expect(generate_matrix.filter_runners(c_minimum_and_maximum_macos))
          .to eq({
            { arch: :arm, name: "macos-15", symbol: :sequoia } => 0.0,
            { arch: :arm, name: "macos-26", symbol: :tahoe }   => 1.0,
          })

        # A requirement excluding all runners must skip macOS, not test them all.
        expect(generate_matrix.filter_runners(c_maximum_macos_below_all_runners)).to eq({})
      end
    end

    context "when cask only supports Linux" do
      it "returns an array including all Linux" do
        expect(generate_matrix.filter_runners(c_linux))
          .to eq({
            { arch: :arm, name: arm_linux_runner, symbol: :linux }  => 1.0,
            { arch: :intel, name: "ubuntu-latest", symbol: :linux } => 1.0,
          })
      end
    end

    context "when cask does not have on_system blocks/calls but has `depends_on arch`" do
      it "returns no runners for an Intel-only macOS cask" do
        expect(generate_matrix.filter_runners(c_depends_macos_on_intel)).to eq({})
      end
    end

    context "when cask has on_system blocks/calls but does not have `depends_on arch`" do
      it "returns an array with combinations of OS and architectures" do
        expect(generate_matrix.filter_runners(c_on_system))
          .to eq({
            { arch: :arm, name: "macos-15", symbol: :sequoia }      => 0.0,
            { arch: :arm, name: "macos-26", symbol: :tahoe }        => 1.0,
            { arch: :arm, name: "xcode-27", symbol: :golden_gate }  => 0.0,
            { arch: :arm, name: arm_linux_runner, symbol: :linux }  => 1.0,
            { arch: :intel, name: "ubuntu-latest", symbol: :linux } => 1.0,
          })
      end
    end

    context "when cask has on_system blocks/calls and `depends_on arch`" do
      it "returns an array with combinations of OS and `depends_on arch` value" do
        expect(generate_matrix.filter_runners(c_on_system_depends_on_intel))
          .to eq({ { arch: :intel, name: "ubuntu-latest", symbol: :linux } => 1.0 })

        expect(generate_matrix.filter_runners(c_on_linux_depends_on_intel))
          .to eq({
            { arch: :arm, name: "macos-15", symbol: :sequoia }      => 0.0,
            { arch: :arm, name: "macos-26", symbol: :tahoe }        => 1.0,
            { arch: :arm, name: "xcode-27", symbol: :golden_gate }  => 0.0,
            { arch: :intel, name: "ubuntu-latest", symbol: :linux } => 1.0,
          })

        expect(generate_matrix.filter_runners(c_on_macos_depends_on_intel))
          .to eq({
            { arch: :intel, name: "ubuntu-latest", symbol: :linux } => 1.0,
            { arch: :arm, name: arm_linux_runner, symbol: :linux }  => 1.0,
          })

        expect(generate_matrix.filter_runners(c_on_macos_depends_on_arm))
          .to eq({
            { arch: :arm, name: "macos-15", symbol: :sequoia }      => 0.0,
            { arch: :arm, name: "macos-26", symbol: :tahoe }        => 1.0,
            { arch: :arm, name: "xcode-27", symbol: :golden_gate }  => 0.0,
            { arch: :arm, name: arm_linux_runner, symbol: :linux }  => 1.0,
            { arch: :intel, name: "ubuntu-latest", symbol: :linux } => 1.0,
          })

        expect(generate_matrix.filter_runners(c_on_system_depends_on_mixed))
          .to eq({ { arch: :arm, name: arm_linux_runner, symbol: :linux } => 1.0 })
      end
    end
  end

  describe "::runners" do
    let(:arm_linux_runner) { OS::LINUX_CI_ARM_RUNNER }

    it "selects one macOS runner and every Linux runner" do
      allow(generate_matrix).to receive(:random_runner) { |runners| runners.keys.first }

      expect(generate_matrix.runners(cask: c).map { |runner| runner.fetch(:name) })
        .to contain_exactly("macos-15", arm_linux_runner, "ubuntu-latest")
    end

    it "selects only Linux runners for an Intel-only macOS cask" do
      expect(generate_matrix.runners(cask: c_on_macos_depends_on_intel).map { |runner| runner.fetch(:name) })
        .to contain_exactly(arm_linux_runner, "ubuntu-latest")
    end
  end
end
