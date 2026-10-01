# typed: true
# frozen_string_literal: true

require "github_runner_matrix"
require "bottle_transition"
require "test/support/fixtures/testball"

RSpec.describe GitHubRunnerMatrix, :no_api do
  let(:newest_supported_macos) do
    MacOSVersion::SYMBOLS.find { |k, _| k == GitHubRunnerMatrix::NEWEST_HOMEBREW_CORE_MACOS_RUNNER }
  end
  let(:testball) { setup_test_runner_formula("testball") }
  let(:testball_depender) { setup_test_runner_formula("testball-depender", ["testball"]) }
  let(:testball_depender_linux) { setup_test_runner_formula("testball-depender-linux", ["testball", :linux]) }
  let(:testball_depender_macos) { setup_test_runner_formula("testball-depender-macos", ["testball", :macos]) }
  let(:testball_depender_intel) do
    setup_test_runner_formula("testball-depender-intel", ["testball", { arch: :x86_64 }])
  end
  let(:testball_depender_arm) { setup_test_runner_formula("testball-depender-arm", ["testball", { arch: :arm64 }]) }
  let(:portable_ruby) { setup_test_runner_formula("portable-ruby") }
  let(:testball_depender_newest) do
    symbol, = newest_supported_macos
    setup_test_runner_formula("testball-depender-newest", ["testball", { macos: symbol }])
  end

  before do
    allow_any_instance_of(BottleTransition).to receive(:required?).and_return(false)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("HOMEBREW_LINUX_SELF_HOSTED", "false").and_return("false")
    allow(ENV).to receive(:fetch).with("HOMEBREW_MACOS_LONG_TIMEOUT", "false").and_return("false")
    ENV["HOMEBREW_MACOS_BUILD_ON_GITHUB_RUNNER"] = "false"
    allow(ENV).to receive(:fetch).with("GITHUB_RUN_ID").and_return("12345")
    allow(ENV).to receive(:fetch).with("HOMEBREW_EVAL_ALL", nil).and_call_original
    allow(ENV).to receive(:fetch).with("HOMEBREW_SIMULATE_MACOS_ON_LINUX", nil).and_call_original
    allow(ENV).to receive(:fetch).with("HOMEBREW_FORBID_PACKAGES_FROM_PATHS", nil).and_call_original
    allow(ENV).to receive(:fetch).with("HOMEBREW_DEVELOPER", nil).and_call_original
    allow(ENV).to receive(:fetch).with("HOMEBREW_NO_INSTALL_FROM_API", nil).and_call_original
  end

  describe "OLDEST_HOMEBREW_CORE_MACOS_RUNNER" do
    it "is not newer than HOMEBREW_MACOS_OLDEST_SUPPORTED" do
      oldest_macos_runner = MacOSVersion.from_symbol(GitHubRunnerMatrix::OLDEST_HOMEBREW_CORE_MACOS_RUNNER)
      expect(oldest_macos_runner).to be <= HOMEBREW_MACOS_OLDEST_SUPPORTED
    end
  end

  describe "#active_runner_specs_hash" do
    it "builds bottles for Golden Gate, Tahoe and Sequoia" do
      runners = described_class.new([], [], all_supported: true, dependent_matrix: false)
                               .active_runner_specs_hash

      expect(runners.map { |runner| runner.fetch(:name) })
        .to eq(["macOS 27-arm64", "macOS 26-arm64", "macOS 15-arm64"])
    end

    it "uses GitHub runners for macOS dependents with a six-hour timeout" do
      allow(Formula).to receive(:all).and_return([testball, testball_depender].map(&:formula))
      runners = described_class.new([testball], [], all_supported: false, dependent_matrix: true)
                               .active_runner_specs_hash

      expect(runners).to include(
        include(name: "macOS 27-arm64", runner: "xcode-27", timeout: 360, cleanup: true),
        include(name: "macOS 26-arm64", runner: "macos-26", timeout: 360),
        include(name: "macOS 15-arm64", runner: "macos-15", timeout: 360),
      )
    end

    it "uses a GitHub runner for Golden Gate bottles when requested" do
      ENV["HOMEBREW_MACOS_BUILD_ON_GITHUB_RUNNER"] = "true"
      runners = described_class.new([testball], [], all_supported: false, dependent_matrix: false)
                               .active_runner_specs_hash

      expect(runners).to include(
        include(name: "macOS 27-arm64", runner: "xcode-27", timeout: 360, cleanup: true),
      )
    end

    it "preserves GitHub runner labels when older macOS symbols are removed" do
      allow(BottleTransition).to receive(:active?).and_return(false)
      stub_const("MacOSVersion::SYMBOLS", { future: "28" }.merge(MacOSVersion::SYMBOLS.except(:golden_gate)))
      stub_const("GitHubRunnerMatrix::NEWEST_HOMEBREW_CORE_MACOS_RUNNER", :future)
      stub_const("GitHubRunnerMatrix::NEWEST_GITHUB_ACTIONS_ARM_MACOS_RUNNER", :future)
      ENV["HOMEBREW_MACOS_BUILD_ON_GITHUB_RUNNER"] = "true"
      runners = described_class.new([], [], all_supported: true, dependent_matrix: false)
                               .active_runner_specs_hash

      expect(runners).to include(
        include(name: "macOS 28-arm64", runner: "xcode-28", timeout: 360, cleanup: true),
        include(name: "macOS 26-arm64", runner: "macos-26", timeout: 360, cleanup: true),
        include(name: "macOS 15-arm64", runner: "macos-15", timeout: 360, cleanup: true),
      )
    end

    context "when bootstrapping a macOS release" do
      before do
        stub_const("GitHubRunnerMatrix::NEWEST_HOMEBREW_CORE_MACOS_RUNNER", :tahoe)
        stub_const("GitHubRunnerMatrix::OLDEST_HOMEBREW_CORE_MACOS_RUNNER", :sonoma)
        stub_const("HOMEBREW_MACOS_NEWEST_SUPPORTED", "26")
      end

      it "assigns exactly the default runners to an unenrolled formula" do
        runners = described_class.new([testball], [], all_supported: false, dependent_matrix: false)
                                 .active_runner_specs_hash

        expect(runners.map { |runner| runner[:name] }).to contain_exactly(
          "Linux arm64", "Linux x86_64", "macOS 26-arm64", "macOS 15-arm64", "macOS 14-arm64"
        )
      end

      it "selects only already-bottled formulae for the transition runner" do
        allow_any_instance_of(BottleTransition).to receive(:required?).with(testball.formula).and_return(true)
        runners = described_class.new([testball, testball_depender], [],
                                      all_supported: false, dependent_matrix: false)
                                 .active_runner_specs_hash

        expect(runners.find { |runner| runner[:name] == "macOS 27-arm64" })
          .to include(testing_formulae: "testball")
      end

      it "does not add transition runners to dependent testing" do
        allow_any_instance_of(BottleTransition).to receive(:required?).and_return(true)
        allow(Formula).to receive(:all).and_return([testball, testball_depender].map(&:formula))
        runners = described_class.new([testball], [], all_supported: false, dependent_matrix: true)
                                 .active_runner_specs_hash

        expect(runners.map { |runner| runner[:name] }).not_to include("macOS 27-arm64")
      end

      it "includes changed dependencies needed by an already-bottled formula" do
        allow_any_instance_of(BottleTransition).to receive(:required?)
          .with(testball_depender.formula).and_return(true)
        runners = described_class.new([testball, testball_depender], [],
                                      all_supported: false, dependent_matrix: false)
                                 .active_runner_specs_hash

        expect(runners.find { |runner| runner[:name] == "macOS 27-arm64" })
          .to include(testing_formulae: "testball,testball-depender")
      end

      test_each([{ maximum_macos: :tahoe }, { arch: :x86_64 }, :linux]) do |requirement|
        it "skips a covered parent whose changed dependency requires #{requirement}" do
          dependency = setup_test_runner_formula("incompatible-dependency", [requirement])
          covered = setup_test_runner_formula("covered", [dependency.name])
          allow_any_instance_of(BottleTransition).to receive(:required?).with(covered.formula).and_return(true)
          runners = described_class.new([dependency, covered], [], all_supported: false, dependent_matrix: false)
                                   .active_runner_specs_hash

          expect(runners.map { |runner| runner[:name] }).to contain_exactly(
            "Linux arm64", "Linux x86_64", "macOS 26-arm64", "macOS 15-arm64", "macOS 14-arm64"
          )
        end
      end

      it "does not reuse a bottle for an incompatible changed dependency" do
        dependency = setup_test_runner_formula("incompatible-dependency", [{ maximum_macos: :tahoe }])
        dependency.formula.bottle_specification.sha256(arm64_golden_gate: "a" * 64)
        covered = setup_test_runner_formula("covered", [dependency.name])
        allow_any_instance_of(BottleTransition).to receive(:required?).with(covered.formula).and_return(true)
        runners = described_class.new([dependency, covered], [], all_supported: false, dependent_matrix: false)
                                 .active_runner_specs_hash

        expect(runners.map { |runner| runner[:name] }).not_to include("macOS 27-arm64")
      end

      it "keeps standard runners when transition prerequisites are missing" do
        testball
        allow_any_instance_of(BottleTransition).to receive(:required?)
          .with(testball_depender.formula).and_return(true)

        runners = described_class.new([testball_depender], [], all_supported: false, dependent_matrix: false)
                                 .active_runner_specs_hash

        expect(runners.map { |runner| runner[:name] }).to contain_exactly(
          "Linux arm64", "Linux x86_64", "macOS 26-arm64", "macOS 15-arm64", "macOS 14-arm64"
        )
      end

      it "does not require build dependencies of unchanged bottled dependencies" do
        setup_test_runner_formula("unbottled-tool")
        dependency = setup_test_runner_formula("bottled-dependency", [{ "unbottled-tool" => :build }])
        dependency.formula.bottle_specification.sha256(arm64_golden_gate: "a" * 64)
        covered = setup_test_runner_formula("covered", [dependency.name])
        allow_any_instance_of(BottleTransition).to receive(:required?).with(covered.formula).and_return(true)
        runners = described_class.new([covered], [], all_supported: false, dependent_matrix: false)
                                 .active_runner_specs_hash

        expect(runners.find { |runner| runner[:name] == "macOS 27-arm64" })
          .to include(testing_formulae: "covered")
      end

      it "allows the runner to check older bottles for unchanged test-only dependencies" do
        dependency = setup_test_runner_formula("test-only-dependency")
        dependency.formula.bottle_specification.sha256(arm64_tahoe: "a" * 64)
        covered = setup_test_runner_formula("covered", [{ dependency.name => :test }])
        allow_any_instance_of(BottleTransition).to receive(:required?).with(covered.formula).and_return(true)
        runners = described_class.new([covered], [], all_supported: false, dependent_matrix: false)
                                 .active_runner_specs_hash

        expect(runners.find { |runner| runner[:name] == "macOS 27-arm64" })
          .to include(testing_formulae: "covered")
      end

      test_each([nil, :tahoe, :arm64_linux]) do |bottle_tag|
        it "skips a test-only dependency with #{bottle_tag || "no"} bottles" do
          dependency = setup_test_runner_formula("test-only-dependency")
          dependency.formula.bottle_specification.sha256(bottle_tag => "a" * 64) if bottle_tag
          covered = setup_test_runner_formula("covered", [{ dependency.name => :test }])
          allow_any_instance_of(BottleTransition).to receive(:required?).with(covered.formula).and_return(true)
          runners = described_class.new([covered], [], all_supported: false, dependent_matrix: false)
                                   .active_runner_specs_hash

          expect(runners.map { |runner| runner[:name] }).to contain_exactly(
            "Linux arm64", "Linux x86_64", "macOS 26-arm64", "macOS 15-arm64", "macOS 14-arm64"
          )
        end
      end

      it "checks dependencies of universal test-only bottles" do
        setup_test_runner_formula("unbottled-tool")
        dependency = setup_test_runner_formula("universal-dependency", ["unbottled-tool"])
        dependency.formula.bottle_specification.sha256(all: "a" * 64)
        covered = setup_test_runner_formula("covered", [{ dependency.name => :test }])
        allow_any_instance_of(BottleTransition).to receive(:required?).with(covered.formula).and_return(true)
        runners = described_class.new([covered], [], all_supported: false, dependent_matrix: false)
                                 .active_runner_specs_hash

        expect(runners.map { |runner| runner[:name] }).not_to include("macOS 27-arm64")
      end

      it "allows older bottles for dependencies of universal test-only bottles" do
        tool = setup_test_runner_formula("older-tool")
        tool.formula.bottle_specification.sha256(arm64_tahoe: "a" * 64)
        dependency = setup_test_runner_formula("universal-dependency", [tool.name])
        dependency.formula.bottle_specification.sha256(all: "a" * 64)
        covered = setup_test_runner_formula("covered", [{ dependency.name => :test }])
        allow_any_instance_of(BottleTransition).to receive(:required?).with(covered.formula).and_return(true)
        runners = described_class.new([covered], [], all_supported: false, dependent_matrix: false)
                                 .active_runner_specs_hash

        expect(runners.find { |runner| runner[:name] == "macOS 27-arm64" })
          .to include(testing_formulae: "covered")
      end

      it "requires current bottles for dependencies used at build, test and runtime" do
        dependency = setup_test_runner_formula("shared-dependency")
        dependency.formula.bottle_specification.sha256(arm64_tahoe: "a" * 64)
        runtime = setup_test_runner_formula("runtime-dependency", [dependency.name])
        runtime.formula.bottle_specification.sha256(arm64_golden_gate: "a" * 64)
        covered = setup_test_runner_formula("covered", [{ dependency.name => [:build, :test] }, runtime.name])
        allow_any_instance_of(BottleTransition).to receive(:required?).with(covered.formula).and_return(true)
        runners = described_class.new([covered], [], all_supported: false, dependent_matrix: false)
                                 .active_runner_specs_hash

        expect(runners.map { |runner| runner[:name] }).not_to include("macOS 27-arm64")
      end

      it "checks build dependencies of universal bottles" do
        setup_test_runner_formula("unbottled-tool")
        dependency = setup_test_runner_formula("universal-dependency", [{ "unbottled-tool" => :build }])
        dependency.formula.bottle_specification.sha256(all: "a" * 64)
        covered = setup_test_runner_formula("covered", [dependency.name])
        allow_any_instance_of(BottleTransition).to receive(:required?).with(covered.formula).and_return(true)
        runners = described_class.new([covered], [], all_supported: false, dependent_matrix: false)
                                 .active_runner_specs_hash

        expect(runners.map { |runner| runner[:name] }).not_to include("macOS 27-arm64")
      end
    end

    it "returns an object that responds to `#to_json`" do
      expect(
        described_class.new([], ["deleted"], all_supported: false, dependent_matrix: false)
                       .active_runner_specs_hash
                       .respond_to?(:to_json),
      ).to be(true)
    end

    it "uses unprivileged Linux containers" do
      linux_containers = described_class.new([], ["deleted"], all_supported: false, dependent_matrix: false)
                                        .active_runner_specs_hash
                                        .filter_map { |runner| runner[:container] }

      expect(linux_containers).to eq(Array.new(2) do
        {
          image:   "ghcr.io/homebrew/brew:main",
          options: "--init --user linuxbrew",
        }
      end)
    end

    it "includes active macOS 11 Portable Ruby runners" do
      runners = described_class.new([portable_ruby], [], all_supported: false, dependent_matrix: false)
                               .active_runner_specs_hash
      intel_runner = runners.find { |runner| runner[:runner] == "macos-15-intel" }
      arm_runner = runners.find { |runner| runner[:name] == "macOS 11-cross arm64" }

      expect(intel_runner).to include(
        name:         "macOS 11-cross x86_64",
        timeout:      360,
        target_macos: "11.7.10",
      )
      expect(arm_runner).to include(
        name:         "macOS 11-cross arm64",
        timeout:      2160,
        target_macos: nil,
        runner:       start_with("11-arm64-cross-"),
      )
    end
  end

  describe "#generate_runners!" do
    it "is idempotent" do
      matrix = described_class.new([], [], all_supported: false, dependent_matrix: false)
      runners = matrix.runners.dup
      matrix.generate_runners!

      expect(matrix.runners).to eq(runners)
    end
  end

  context "when there are no testing formulae and no deleted formulae" do
    it "activates no test runners" do
      expect(described_class.new([], [], all_supported: false, dependent_matrix: false).runners.any?(&:active))
        .to be(false)
    end

    it "activates no dependent runners" do
      expect(described_class.new([], [], all_supported: false, dependent_matrix: true).runners.any?(&:active))
        .to be(false)
    end
  end

  context "when passed `--all-supported`" do
    it "activates all runners" do
      expect(described_class.new([], [], all_supported: true, dependent_matrix: false).runners.all?(&:active))
        .to be(true)
    end
  end

  context "when there are testing formulae and no deleted formulae" do
    context "when it is a matrix for the `tests` job" do
      context "when testing formulae have no requirements" do
        it "activates all runners" do
          expect(described_class.new([testball], [], all_supported: false, dependent_matrix: false)
                                .runners
                                .all?(&:active))
            .to be(true)
        end
      end

      context "when testing formulae require Linux" do
        it "activates only the Linux runners" do
          runner_matrix = described_class.new([testball_depender_linux], [],
                                              all_supported:    false,
                                              dependent_matrix: false)

          expect(runner_matrix.runners.all?(&:active)).to be(false)
          expect(runner_matrix.runners.any?(&:active)).to be(true)
          expect(get_runner_names(runner_matrix)).to eq(["Linux arm64", "Linux x86_64"])
        end
      end

      context "when testing formulae require macOS" do
        it "activates only the macOS runners" do
          runner_matrix = described_class.new([testball_depender_macos], [],
                                              all_supported:    false,
                                              dependent_matrix: false)

          expect(runner_matrix.runners.all?(&:active)).to be(false)
          expect(runner_matrix.runners.any?(&:active)).to be(true)
          expect(get_runner_names(runner_matrix)).to eq(get_runner_names(runner_matrix, :macos?))
        end
      end

      context "when testing formulae require Intel" do
        it "activates only the Intel runners" do
          runner_matrix = described_class.new([testball_depender_intel], [],
                                              all_supported:    false,
                                              dependent_matrix: false)

          expect(runner_matrix.runners.all?(&:active)).to be(false)
          expect(runner_matrix.runners.any?(&:active)).to be(true)
          expect(get_runner_names(runner_matrix)).to eq(get_runner_names(runner_matrix, :x86_64?))
        end
      end

      context "when testing formulae require ARM" do
        it "activates only the ARM runners" do
          runner_matrix = described_class.new([testball_depender_arm], [],
                                              all_supported:    false,
                                              dependent_matrix: false)

          expect(runner_matrix.runners.all?(&:active)).to be(false)
          expect(runner_matrix.runners.any?(&:active)).to be(true)
          expect(get_runner_names(runner_matrix)).to eq(get_runner_names(runner_matrix, :arm64?))
        end
      end

      context "when testing formulae require a macOS version" do
        it "activates only the suitable macOS runners" do
          _, v = newest_supported_macos
          runner_matrix = described_class.new([testball_depender_newest], [],
                                              all_supported:    false,
                                              dependent_matrix: false)

          expect(runner_matrix.runners.all?(&:active)).to be(false)
          expect(runner_matrix.runners.any?(&:active)).to be(true)
          expect(get_runner_names(runner_matrix).sort).to eq(["macOS #{v}-arm64"])
        end
      end
    end

    context "when it is a matrix for the `test_deps` job" do
      context "when testing formulae have no dependents" do
        it "activates no runners" do
          allow(Formula).to receive(:all).and_return([testball].map(&:formula))

          expect(described_class.new([testball], [], all_supported: false, dependent_matrix: true)
                                .runners
                                .any?(&:active))
            .to be(false)
        end
      end

      context "when testing formulae have dependents" do
        context "when dependents have no requirements" do
          it "activates all runners" do
            allow(Formula).to receive(:all).and_return([testball, testball_depender].map(&:formula))

            expect(described_class.new([testball], [], all_supported: false, dependent_matrix: true)
                                  .runners
                                  .all?(&:active))
              .to be(true)
          end

          it "splits active runners into shards" do
            macos = GitHubRunnerMatrix::NEWEST_HOMEBREW_CORE_MACOS_RUNNER
            macos_version = MacOSVersion.from_symbol(macos)
            stub_const("GitHubRunnerMatrix::OLDEST_HOMEBREW_CORE_MACOS_RUNNER", macos)
            stub_const("OS::LINUX_CI_ARM_RUNNER", "ubuntu-24.04-arm")

            allow(ENV).to receive(:fetch).with("HOMEBREW_MACOS_LONG_TIMEOUT", "false").and_return("true")
            allow(ENV).to receive(:key?).and_call_original
            allow(ENV).to receive(:key?).with("GITHUB_ACTIONS").and_return(true)
            allow(Formula).to receive(:all).and_return([testball, testball_depender].map(&:formula))

            runners = described_class.new([testball], [],
                                          all_supported:    false,
                                          dependent_matrix: true,
                                          dependent_shards: 2)
                                     .active_runner_specs_hash

            expect(runners).to all(include(:formulae_dependents_shard))
            expect(runners.map { |runner| runner.fetch(:formulae_dependents_shard) }.uniq).to eq(["1/2", "2/2"])
            expect(runners.map { |runner| runner.fetch(:name) }).to all(match(%r{ shard [12]/2\z}))
            expect(runners.map { |runner| runner.fetch(:runner) }).to eq([
              "ubuntu-24.04-arm",
              "ubuntu-24.04-arm",
              "ubuntu-latest",
              "ubuntu-latest",
              "#{macos_version}-arm64-12345-deps1-long",
              "#{macos_version}-arm64-12345-deps2-long",
            ])
          end
        end

        context "when dependents require Linux" do
          it "activates only Linux runners" do
            allow(Formula).to receive(:all).and_return([testball, testball_depender_linux].map(&:formula))

            runner_matrix = described_class.new([testball], [], all_supported: false, dependent_matrix: true)
            expect(runner_matrix.runners.all?(&:active)).to be(false)
            expect(runner_matrix.runners.any?(&:active)).to be(true)
            expect(get_runner_names(runner_matrix)).to eq(get_runner_names(runner_matrix, :linux?))
          end
        end

        context "when dependents require macOS" do
          it "activates only macOS runners" do
            allow(Formula).to receive(:all).and_return([testball, testball_depender_macos].map(&:formula))

            runner_matrix = described_class.new([testball], [], all_supported: false, dependent_matrix: true)
            expect(runner_matrix.runners.all?(&:active)).to be(false)
            expect(runner_matrix.runners.any?(&:active)).to be(true)
            expect(get_runner_names(runner_matrix)).to eq(get_runner_names(runner_matrix, :macos?))
          end
        end

        context "when dependents require an Intel architecture" do
          it "activates only Intel runners" do
            allow(Formula).to receive(:all).and_return([testball, testball_depender_intel].map(&:formula))

            runner_matrix = described_class.new([testball], [], all_supported: false, dependent_matrix: true)
            expect(runner_matrix.runners.all?(&:active)).to be(false)
            expect(runner_matrix.runners.any?(&:active)).to be(true)
            expect(get_runner_names(runner_matrix)).to eq(get_runner_names(runner_matrix, :x86_64?))
          end
        end

        context "when dependents require an ARM architecture" do
          it "activates only ARM runners" do
            allow(Formula).to receive(:all).and_return([testball, testball_depender_arm].map(&:formula))

            runner_matrix = described_class.new([testball], [], all_supported: false, dependent_matrix: true)
            expect(runner_matrix.runners.all?(&:active)).to be(false)
            expect(runner_matrix.runners.any?(&:active)).to be(true)
            expect(get_runner_names(runner_matrix)).to eq(get_runner_names(runner_matrix, :arm64?))
          end
        end

        context "when dependents are disabled" do
          it "activates no runners" do
            testball_depender_disabled = setup_test_runner_formula("testball-depender-disabled", ["testball"])

            disabled_formula = testball_depender_disabled.formula
            allow(disabled_formula).to receive(:disabled?).and_return(true)
            allow(Formula).to receive(:all).and_return([testball.formula, disabled_formula])

            runner_matrix = described_class.new([testball], [], all_supported: false, dependent_matrix: true)
            expect(runner_matrix.runners.any?(&:active)).to be(false)
          end
        end

        context "when dependents are deprecated" do
          it "activates no runners" do
            testball_depender_deprecated = setup_test_runner_formula("testball-depender-deprecated", ["testball"])

            deprecated_formula = testball_depender_deprecated.formula
            allow(deprecated_formula).to receive(:deprecated?).and_return(true)
            allow(Formula).to receive(:all).and_return([testball.formula, deprecated_formula])

            runner_matrix = described_class.new([testball], [], all_supported: false, dependent_matrix: true)
            expect(runner_matrix.runners.any?(&:active)).to be(false)
          end
        end
      end
    end
  end

  context "when there are deleted formulae" do
    context "when it is a matrix for the `tests` job" do
      it "activates all runners" do
        expect(described_class.new([], ["deleted"], all_supported: false, dependent_matrix: false)
                              .runners
                              .all?(&:active))
          .to be(true)
      end
    end

    context "when it is a matrix for the `test_deps` job" do
      context "when there are no testing formulae" do
        it "activates no runners" do
          expect(described_class.new([], ["deleted"], all_supported: false, dependent_matrix: true)
                                .runners
                                .any?(&:active))
            .to be(false)
        end
      end

      context "when there are testing formulae with no dependents" do
        it "activates no runners" do
          testing_formulae = [testball]
          runner_matrix = described_class.new(testing_formulae, ["deleted"],
                                              all_supported:    false,
                                              dependent_matrix: true)

          allow(Formula).to receive(:all).and_return(testing_formulae.map(&:formula))

          expect(runner_matrix.runners.none?(&:active)).to be(true)
        end
      end

      context "when there are testing formulae with dependents" do
        context "when dependent formulae have no requirements" do
          it "activates the applicable runners" do
            allow(Formula).to receive(:all).and_return([testball, testball_depender].map(&:formula))

            testing_formulae = [testball]
            expect(described_class.new(testing_formulae, ["deleted"], all_supported: false, dependent_matrix: true)
                                  .runners
                                  .all?(&:active))
              .to be(true)
          end
        end

        context "when dependent formulae have requirements" do
          context "when dependent formulae require Linux" do
            it "activates the applicable runners" do
              allow(Formula).to receive(:all).and_return([testball, testball_depender_linux].map(&:formula))

              matrix = described_class.new([testball], ["deleted"], all_supported: false, dependent_matrix: true)
              expect(get_runner_names(matrix)).to eq(["Linux arm64", "Linux x86_64"])

              allow(ENV).to receive(:fetch).with("HOMEBREW_LINUX_SELF_HOSTED", "false").and_return("true")
              matrix = described_class.new([testball], ["deleted"], all_supported: false, dependent_matrix: true)
              expect(get_runner_names(matrix)).to eq(["Linux arm64", "Linux x86_64"])
            end
          end

          context "when dependent formulae require macOS" do
            it "activates the applicable runners" do
              allow(Formula).to receive(:all).and_return([testball, testball_depender_macos].map(&:formula))

              matrix = described_class.new([testball], ["deleted"], all_supported: false, dependent_matrix: true)
              expect(get_runner_names(matrix)).to eq(get_runner_names(matrix, :macos?))
            end
          end
        end
      end
    end
  end

  def get_runner_names(runner_matrix, predicate = :active)
    runner_matrix.runners
                 .select(&predicate)
                 .map { |runner| runner.spec.name }
  end

  def setup_test_runner_formula(name, dependencies = [], **kwargs)
    f = formula name do
      T.bind(self, T.class_of(Formula))
      url "https://brew.sh/#{name}-1.0.tar.gz"
      dependencies.each { |dependency| depends_on dependency }

      kwargs.each do |k, v|
        public_send(:"on_#{k}") do
          v.each do |dep|
            depends_on dep
          end
        end
      end
    end

    stub_formula_loader f
    TestRunnerFormula.new(f, include_uninstalled: true)
  end
end
