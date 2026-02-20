# frozen_string_literal: true

require "sharded_runner_matrix"
require "test/support/fixtures/testball"

RSpec.describe ShardedRunnerMatrix, :no_api do
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
  let(:testball_depender_newest) do
    symbol, = newest_supported_macos
    setup_test_runner_formula("testball-depender-newest", ["testball", { macos: symbol }])
  end

  describe "DEFAULT_SHARD_MAX_RUNNERS" do
    it "defaults to one so sharding is opt-in" do
      expect(described_class::DEFAULT_SHARD_MAX_RUNNERS).to eq(1)
    end
  end

  describe "#active_runner_specs_hash" do
    it "expands dependent matrix rows using per-runner shard counts" do
      allow(Homebrew::EnvConfig).to receive(:eval_all?).and_return(true)
      allow(Formula).to receive(:all).and_return(
        [testball, testball_depender, testball_depender_macos, testball_depender_newest].map(&:formula),
      )

      runner_specs = described_class.new(
        [testball], [],
        all_supported:              false,
        dependent_matrix:           true,
        shard_max_runners:          3,
        shard_min_items_per_runner: 1
      ).active_runner_specs_hash

      grouped_runner_specs = runner_specs.group_by { |runner_spec| runner_spec.fetch(:runner) }
      per_runner_counts = grouped_runner_specs.values.map(&:count)
      expect(per_runner_counts).to include(3)

      grouped_runner_specs.each_value do |runner_spec_rows|
        expected_count = runner_spec_rows.count
        expect(runner_spec_rows).to all(include(shard_count: expected_count))
        expect(runner_spec_rows.map { |runner_spec| runner_spec.fetch(:shard_index) }.sort)
          .to eq((1..expected_count).to_a)
      end
    end

    it "clamps shard counts to the configured maximum" do
      allow(Homebrew::EnvConfig).to receive(:eval_all?).and_return(true)
      allow(Formula).to receive(:all).and_return(
        [testball, testball_depender, testball_depender_linux, testball_depender_macos].map(&:formula),
      )

      runner_specs = described_class.new(
        [testball], [],
        all_supported:              false,
        dependent_matrix:           true,
        shard_max_runners:          2,
        shard_min_items_per_runner: 1
      ).active_runner_specs_hash

      grouped_runner_specs = runner_specs.group_by { |runner_spec| runner_spec.fetch(:runner) }
      expect(grouped_runner_specs.values).to all(satisfy { |runner_spec_rows| runner_spec_rows.count == 2 })
      expect(runner_specs.map { |runner_spec| runner_spec.fetch(:shard_count) }.uniq).to eq([2])
    end

    it "supports custom shard metadata keys" do
      allow(Homebrew::EnvConfig).to receive(:eval_all?).and_return(true)
      allow(Formula).to receive(:all).and_return([testball, testball_depender].map(&:formula))

      runner_specs = described_class.new(
        [testball], [],
        all_supported:              false,
        dependent_matrix:           true,
        shard_max_runners:          2,
        shard_min_items_per_runner: 1,
        shard_count_key:            ShardedRunnerMatrix::ShardCountKey::DependentShardCount,
        shard_index_key:            ShardedRunnerMatrix::ShardIndexKey::DependentShardIndex
      ).active_runner_specs_hash

      expect(runner_specs).to all(include(:dependent_shard_count, :dependent_shard_index))
      expect(runner_specs).to all(satisfy do |runner_spec|
        runner_spec.exclude?(:shard_count) && runner_spec.exclude?(:shard_index)
      end)
    end
  end

  describe "argument validation" do
    it "raises for invalid shard max runners values" do
      expect do
        described_class.new(
          [], ["deleted"],
          all_supported:     false,
          dependent_matrix:  true,
          shard_max_runners: 0
        )
      end.to raise_error(ArgumentError, /shard_max_runners/)
    end

    it "raises for invalid shard min items per runner values" do
      expect do
        described_class.new(
          [], ["deleted"],
          all_supported:              false,
          dependent_matrix:           true,
          shard_min_items_per_runner: 0
        )
      end.to raise_error(ArgumentError, /shard_min_items_per_runner/)
    end
  end

  define_method(:setup_test_runner_formula) do |name, dependencies = [], **kwargs|
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
