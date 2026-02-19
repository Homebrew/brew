# frozen_string_literal: true

require "dependent_shard_matrix"

RSpec.describe DependentShardMatrix do
  let(:runner_a_spec_hash) do
    {
      name:             "Runner A",
      runner:           "runner-a",
      timeout:          60,
      cleanup:          false,
      testing_formulae: "testball",
    }
  end
  let(:runner_b_spec_hash) do
    {
      name:             "Runner B",
      runner:           "runner-b",
      timeout:          60,
      cleanup:          false,
      testing_formulae: "testball",
    }
  end
  let(:runner_a_spec) { instance_double(MacOSRunnerSpec, to_h: runner_a_spec_hash) }
  let(:runner_b_spec) { instance_double(MacOSRunnerSpec, to_h: runner_b_spec_hash) }
  let(:runner_a) { instance_double(GitHubRunner, spec: runner_a_spec) }
  let(:runner_b) { instance_double(GitHubRunner, spec: runner_b_spec) }

  describe "#runner_specs_hash" do
    it "expands each runner by its shard count" do
      matrix = described_class.new(
        active_runners:                  [runner_a, runner_b],
        dependent_count_by_runner:       { runner_a => 0, runner_b => 5 },
        shard_max_runners:               4,
        shard_min_dependents_per_runner: 2,
        shard_runner_load_factor:        1.0,
      )

      specs = matrix.runner_specs_hash
      grouped_specs = specs.group_by { |spec| spec.fetch(:runner) }

      expect(grouped_specs.fetch("runner-a").count).to eq(1)
      expect(grouped_specs.fetch("runner-b").count).to eq(2)
      expect(grouped_specs.fetch("runner-b").map { |spec| spec.fetch(:dependent_shard_index) }).to eq([1, 2])
      expect(grouped_specs.fetch("runner-b")).to all(include(dependent_shard_count: 2))
    end

    it "keeps a single shard when dependents do not reach minimum-per-runner" do
      matrix = described_class.new(
        active_runners:                  [runner_a],
        dependent_count_by_runner:       { runner_a => 5 },
        shard_max_runners:               4,
        shard_min_dependents_per_runner: 7,
        shard_runner_load_factor:        1.0,
      )

      specs = matrix.runner_specs_hash

      expect(specs.count).to eq(1)
      expect(specs.first).to include(dependent_shard_count: 1, dependent_shard_index: 1)
    end

    it "clamps shard count to the configured maximum" do
      matrix = described_class.new(
        active_runners:                  [runner_a],
        dependent_count_by_runner:       { runner_a => 9 },
        shard_max_runners:               2,
        shard_min_dependents_per_runner: 1,
        shard_runner_load_factor:        1.0,
      )

      specs = matrix.runner_specs_hash

      expect(specs.count).to eq(2)
      expect(specs).to all(include(dependent_shard_count: 2))
      expect(specs.map { |spec| spec.fetch(:dependent_shard_index) }).to eq([1, 2])
    end

    it "activates extra shards when load factor allows slightly under-minimum shards" do
      matrix = described_class.new(
        active_runners:                  [runner_a],
        dependent_count_by_runner:       { runner_a => 10 },
        shard_max_runners:               4,
        shard_min_dependents_per_runner: 7,
        shard_runner_load_factor:        0.7,
      )

      specs = matrix.runner_specs_hash

      expect(specs.count).to eq(2)
      expect(specs).to all(include(dependent_shard_count: 2))
      expect(specs.map { |spec| spec.fetch(:dependent_shard_index) }).to eq([1, 2])
    end
  end

  describe "argument validation" do
    it "raises when shard_max_runners is less than one" do
      expect do
        described_class.new(
          active_runners:                  [],
          dependent_count_by_runner:       {},
          shard_max_runners:               0,
          shard_min_dependents_per_runner: 1,
          shard_runner_load_factor:        1.0,
        )
      end.to raise_error(ArgumentError, /shard_max_runners/)
    end

    it "raises when shard_min_dependents_per_runner is less than one" do
      expect do
        described_class.new(
          active_runners:                  [],
          dependent_count_by_runner:       {},
          shard_max_runners:               1,
          shard_min_dependents_per_runner: 0,
          shard_runner_load_factor:        1.0,
        )
      end.to raise_error(ArgumentError, /shard_min_dependents_per_runner/)
    end

    it "raises when shard_runner_load_factor is out of range" do
      expect do
        described_class.new(
          active_runners:                  [],
          dependent_count_by_runner:       {},
          shard_max_runners:               1,
          shard_min_dependents_per_runner: 1,
          shard_runner_load_factor:        0.0,
        )
      end.to raise_error(ArgumentError, /shard_runner_load_factor/)
    end
  end
end
