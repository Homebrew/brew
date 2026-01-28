# frozen_string_literal: true

require "github_runner_matrix"
require "test/support/fixtures/testball"

RSpec.describe GitHubRunnerMatrix, :no_api do
  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("HOMEBREW_LINUX_RUNNER").and_return("ubuntu-latest")
    allow(ENV).to receive(:fetch).with("HOMEBREW_MACOS_LONG_TIMEOUT", "false").and_return("false")
    allow(ENV).to receive(:fetch).with("HOMEBREW_MACOS_BUILD_ON_GITHUB_RUNNER", "false").and_return("false")
    allow(ENV).to receive(:fetch).with("GITHUB_RUN_ID").and_return("12345")
    allow(ENV).to receive(:fetch).with("HOMEBREW_EVAL_ALL", nil).and_call_original
    allow(ENV).to receive(:fetch).with("HOMEBREW_SIMULATE_MACOS_ON_LINUX", nil).and_call_original
    allow(ENV).to receive(:fetch).with("HOMEBREW_FORBID_PACKAGES_FROM_PATHS", nil).and_call_original
    allow(ENV).to receive(:fetch).with("HOMEBREW_DEVELOPER", nil).and_call_original
    allow(ENV).to receive(:fetch).with("HOMEBREW_NO_INSTALL_FROM_API", nil).and_call_original
  end

  let(:newest_supported_macos) do
    MacOSVersion::SYMBOLS.find { |k, _| k == described_class::NEWEST_HOMEBREW_CORE_MACOS_RUNNER }
  end

  let(:testball) { setup_test_runner_formula("testball") }
  let(:testball_depender) { setup_test_runner_formula("testball-depender", ["testball"]) }
  let(:testball_depender_linux) { setup_test_runner_formula("testball-depender-linux", ["testball", :linux]) }
  let(:testball_depender_macos) { setup_test_runner_formula("testball-depender-macos", ["testball", :macos]) }
  let(:testball_depender_intel) do
    setup_test_runner_formula("testball-depender-intel", ["testball", { arch: :x86_64 }])
  end
  let(:testball_depender_arm) { setup_test_runner_formula("testball-depender-arm", ["testball", { arch: :arm64 }]) }
  let(:testball_depender_newest) do
    symbol, = newest_supported_macos
    setup_test_runner_formula("testball-depender-newest", ["testball", { macos: symbol }])
  end

  describe "OLDEST_HOMEBREW_CORE_MACOS_RUNNER" do
    it "is not newer than HOMEBREW_MACOS_OLDEST_SUPPORTED" do
      oldest_macos_runner = MacOSVersion.from_symbol(described_class::OLDEST_HOMEBREW_CORE_MACOS_RUNNER)
      expect(oldest_macos_runner).to be <= HOMEBREW_MACOS_OLDEST_SUPPORTED
    end
  end

  describe "#active_runner_specs_hash" do
    it "returns an object that responds to `#to_json`" do
      expect(
        described_class.new([], ["deleted"], all_supported: false, dependent_matrix: false)
                       .active_runner_specs_hash
                       .respond_to?(:to_json),
      ).to be(true)
    end
  end

  describe "#generate_runners!" do
    it "is idempotent" do
      matrix = described_class.new([], [], all_supported: false, dependent_matrix: false)
      runners = matrix.runners.dup
      matrix.send(:generate_runners!)

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
          expect(get_runner_names(runner_matrix)).to eq(["Linux x86_64", "Linux arm64"])
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
        it "activates the Linux runners and suitable macOS runners" do
          _, v = newest_supported_macos
          runner_matrix = described_class.new([testball_depender_newest], [],
                                              all_supported:    false,
                                              dependent_matrix: false)

          expect(runner_matrix.runners.all?(&:active)).to be(false)
          expect(runner_matrix.runners.any?(&:active)).to be(true)
          expect(get_runner_names(runner_matrix).sort).to eq(["Linux arm64", "Linux x86_64", "macOS #{v}-arm64"])
        end
      end
    end

    context "when it is a matrix for the `test_deps` job" do
      context "when testing formulae have no dependents" do
        it "activates no runners" do
          allow(Homebrew::EnvConfig).to receive(:eval_all?).and_return(true)
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
            allow(Homebrew::EnvConfig).to receive(:eval_all?).and_return(true)
            allow(Formula).to receive(:all).and_return([testball, testball_depender].map(&:formula))

            expect(described_class.new([testball], [], all_supported: false, dependent_matrix: true)
                                  .runners
                                  .all?(&:active))
              .to be(true)
          end
        end

        context "when dependents require Linux" do
          it "activates only Linux runners" do
            allow(Homebrew::EnvConfig).to receive(:eval_all?).and_return(true)
            allow(Formula).to receive(:all).and_return([testball, testball_depender_linux].map(&:formula))

            runner_matrix = described_class.new([testball], [], all_supported: false, dependent_matrix: true)
            expect(runner_matrix.runners.all?(&:active)).to be(false)
            expect(runner_matrix.runners.any?(&:active)).to be(true)
            expect(get_runner_names(runner_matrix)).to eq(get_runner_names(runner_matrix, :linux?))
          end
        end

        context "when dependents require macOS" do
          it "activates only macOS runners" do
            allow(Homebrew::EnvConfig).to receive(:eval_all?).and_return(true)
            allow(Formula).to receive(:all).and_return([testball, testball_depender_macos].map(&:formula))

            runner_matrix = described_class.new([testball], [], all_supported: false, dependent_matrix: true)
            expect(runner_matrix.runners.all?(&:active)).to be(false)
            expect(runner_matrix.runners.any?(&:active)).to be(true)
            expect(get_runner_names(runner_matrix)).to eq(get_runner_names(runner_matrix, :macos?))
          end
        end

        context "when dependents require an Intel architecture" do
          it "activates only Intel runners" do
            allow(Homebrew::EnvConfig).to receive(:eval_all?).and_return(true)
            allow(Formula).to receive(:all).and_return([testball, testball_depender_intel].map(&:formula))

            runner_matrix = described_class.new([testball], [], all_supported: false, dependent_matrix: true)
            expect(runner_matrix.runners.all?(&:active)).to be(false)
            expect(runner_matrix.runners.any?(&:active)).to be(true)
            expect(get_runner_names(runner_matrix)).to eq(get_runner_names(runner_matrix, :x86_64?))
          end
        end

        context "when dependents require an ARM architecture" do
          it "activates only ARM runners" do
            allow(Homebrew::EnvConfig).to receive(:eval_all?).and_return(true)
            allow(Formula).to receive(:all).and_return([testball, testball_depender_arm].map(&:formula))

            runner_matrix = described_class.new([testball], [], all_supported: false, dependent_matrix: true)
            expect(runner_matrix.runners.all?(&:active)).to be(false)
            expect(runner_matrix.runners.any?(&:active)).to be(true)
            expect(get_runner_names(runner_matrix)).to eq(get_runner_names(runner_matrix, :arm64?))
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

          allow(Homebrew::EnvConfig).to receive(:eval_all?).and_return(true)
          allow(Formula).to receive(:all).and_return(testing_formulae.map(&:formula))

          expect(runner_matrix.runners.none?(&:active)).to be(true)
        end
      end

      context "when there are testing formulae with dependents" do
        context "when dependent formulae have no requirements" do
          it "activates the applicable runners" do
            allow(Homebrew::EnvConfig).to receive(:eval_all?).and_return(true)
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
              allow(Homebrew::EnvConfig).to receive(:eval_all?).and_return(true)
              allow(Formula).to receive(:all).and_return([testball, testball_depender_linux].map(&:formula))

              matrix = described_class.new([testball], ["deleted"], all_supported: false, dependent_matrix: true)
              expect(get_runner_names(matrix)).to eq(["Linux x86_64", "Linux arm64"])

              allow(ENV).to receive(:[]).with("HOMEBREW_LINUX_RUNNER").and_return("linux-self-hosted-1")
              matrix = described_class.new([testball], ["deleted"], all_supported: false, dependent_matrix: true)
              expect(get_runner_names(matrix)).to eq(["Linux x86_64"])
            end
          end

          context "when dependent formulae require macOS" do
            it "activates the applicable runners" do
              allow(Homebrew::EnvConfig).to receive(:eval_all?).and_return(true)
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
      url "https://brew.sh/#{name}-1.0.tar.gz"
      dependencies.each { |dependency| depends_on dependency }

      kwargs.each do |k, v|
        send(:"on_#{k}") do
          v.each do |dep|
            depends_on dep
          end
        end
      end
    end

    stub_formula_loader f
    TestRunnerFormula.new(f)
  end
end
