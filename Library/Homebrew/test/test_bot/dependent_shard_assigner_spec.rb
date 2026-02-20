# frozen_string_literal: true

require "test_bot/dependent_shard_assigner"

RSpec.describe Homebrew::TestBot::DependentShardAssigner do
  let(:formulae) { %w[alpha beta gamma delta epsilon zeta] }

  define_method(:full_name) do |formula_name|
    "homebrew/core/#{formula_name}"
  end

  define_method(:feature_spread_score) do |assignments, dependency_features|
    dependency_features.values.flatten.uniq.sum do |feature|
      shards_with_feature = assignments.filter_map do |formula_name, shard_index|
        shard_index if dependency_features.fetch(formula_name, []).include?(feature)
      end.uniq
      shards_with_feature.length - 1
    end
  end

  define_method(:round_robin_assignments) do |formula_names, shard_count|
    formula_names.sort.each_with_index.to_h do |formula_name, index|
      [formula_name, index % shard_count]
    end
  end

  define_method(:shard_loads) do |assignments, dependency_features, shard_count|
    loads = Array.new(shard_count, 0)
    assignments.each do |formula_name, shard_index|
      loads[shard_index] += [dependency_features.fetch(formula_name, []).length, 1].max
    end
    loads
  end

  before do
    allow(Formulary).to receive(:factory) do |formula_name|
      instance_double(Formula, full_name: full_name(formula_name))
    end
  end

  describe "#assignments" do
    it "deterministically assigns the same shard members" do
      dependency_features = formulae.to_h do |formula_name|
        [full_name(formula_name), ["dep-#{formula_name}"]]
      end

      assigner = described_class.new(shard_count: 3, dependency_features:)
      assignments_a = assigner.assignments(formulae)
      assignments_b = assigner.assignments(formulae)

      expect(assignments_a).to eq(assignments_b)
    end

    it "is deterministic for highly connected dependency graphs" do
      dependency_features = formulae.to_h do |formula_name|
        [full_name(formula_name), %w[shared-1 shared-2 shared-3]]
      end

      assigner = described_class.new(shard_count: 3, dependency_features:)
      assignments_a = assigner.assignments(formulae)
      assignments_b = assigner.assignments(formulae)

      expect(assignments_a).to eq(assignments_b)
    end

    it "prefers locality versus a naive round-robin baseline" do
      dependency_features = {
        full_name("alpha")   => %w[shared-a shared-b alpha-only],
        full_name("beta")    => %w[shared-a shared-b beta-only],
        full_name("gamma")   => %w[shared-a shared-b gamma-only],
        full_name("delta")   => %w[shared-x shared-y delta-only],
        full_name("epsilon") => %w[shared-x shared-y epsilon-only],
        full_name("zeta")    => %w[shared-x shared-y zeta-only],
      }

      assigner = described_class.new(shard_count: 2, dependency_features:)
      locality_assignments = assigner.assignments(formulae)
      baseline_assignments = round_robin_assignments(formulae.map { |formula_name| full_name(formula_name) }, 2)

      locality_spread = feature_spread_score(locality_assignments, dependency_features)
      baseline_spread = feature_spread_score(baseline_assignments, dependency_features)

      expect(locality_spread).to be < baseline_spread
    end

    it "keeps cyclic dependents together in the same shard" do
      dependency_features = {
        full_name("alpha") => ["dep-alpha"],
        full_name("beta")  => ["dep-beta"],
        full_name("gamma") => ["dep-gamma"],
        full_name("delta") => ["dep-delta"],
      }
      dependency_graph = {
        full_name("alpha") => [full_name("beta")],
        full_name("beta")  => [full_name("alpha")],
      }

      assigner = described_class.new(shard_count: 2, dependency_features:, dependency_graph:)
      assignments = assigner.assignments(%w[alpha beta gamma delta])

      expect(assignments.fetch(full_name("alpha"))).to eq(assignments.fetch(full_name("beta")))
    end

    it "splits oversized strongly connected components to preserve shard parallelism" do
      dependency_features = %w[alpha beta gamma delta epsilon].to_h do |formula_name|
        [full_name(formula_name), ["dep-#{formula_name}"]]
      end
      dependency_graph = {
        full_name("alpha") => [full_name("beta")],
        full_name("beta")  => [full_name("gamma")],
        full_name("gamma") => [full_name("delta")],
        full_name("delta") => [full_name("alpha")],
      }

      assigner = described_class.new(shard_count: 2, dependency_features:, dependency_graph:)
      assignments = assigner.assignments(%w[alpha beta gamma delta epsilon])

      cycle_shards = %w[alpha beta gamma delta].map { |formula_name| assignments.fetch(full_name(formula_name)) }.uniq
      expect(cycle_shards.length).to be > 1
      expected_full_names = %w[alpha beta gamma delta epsilon].map { |formula_name| full_name(formula_name) }.sort
      expect(assignments.keys.sort).to eq(expected_full_names)
    end

    it "balances runtime-heavy dependents across shards" do
      dependency_features = {
        full_name("hot-a")  => (1..30).map { |index| "hot-shared-#{index}" } + ["hot-a-only"],
        full_name("hot-b")  => (1..30).map { |index| "hot-shared-#{index}" } + ["hot-b-only"],
        full_name("hot-c")  => (1..30).map { |index| "hot-shared-#{index}" } + ["hot-c-only"],
        full_name("cold-a") => %w[cold-shared cold-a-only],
        full_name("cold-b") => %w[cold-shared cold-b-only],
        full_name("cold-c") => %w[cold-shared cold-c-only],
      }
      formulae = %w[hot-a hot-b hot-c cold-a cold-b cold-c]

      assigner = described_class.new(shard_count: 2, dependency_features:)
      assignments = assigner.assignments(formulae)
      loads = shard_loads(assignments, dependency_features, 2)

      hot_shards = %w[hot-a hot-b hot-c].map { |formula_name| assignments.fetch(full_name(formula_name)) }.uniq
      expect(hot_shards.length).to be > 1
      expect(loads.max - loads.min).to be <= 31
    end

    it "supports full-name string inputs without Formulary lookups" do
      dependency_features = {
        full_name("alpha") => ["dep-alpha"],
        full_name("beta")  => ["dep-beta"],
      }
      assigner = described_class.new(shard_count: 2, dependency_features:)

      expect(Formulary).not_to receive(:factory)
      assignments = assigner.assignments([full_name("alpha"), full_name("beta")])

      expect(assignments.keys.sort).to eq([full_name("alpha"), full_name("beta")])
    end

    it "deduplicates repeated dependent full names at assignment time" do
      dependency_features = {
        full_name("alpha") => ["dep-alpha"],
        full_name("beta")  => ["dep-beta"],
      }
      assigner = described_class.new(shard_count: 2, dependency_features:)
      assignments = assigner.assignments([full_name("alpha"), full_name("alpha"), full_name("beta")])

      expect(assignments.keys.sort).to eq([full_name("alpha"), full_name("beta")])
    end
  end

  describe "#shard_formulae" do
    it "assigns disjoint shards whose union matches the original set" do
      assigner = described_class.new(shard_count: 3, dependency_features: {})
      shards = (1..3).map { |shard_index| assigner.shard_formulae(formulae, shard_index:) }

      expect(shards.combination(2).all? do |first_shard, second_shard|
        !first_shard.intersect?(second_shard)
      end).to be(true)
      expect(shards.flatten.sort).to eq(formulae.sort)
    end

    it "shards dependent formula objects by full_name" do
      dependent_formulae = (1..20).map do |index|
        instance_double(Formula, full_name: "homebrew/core/dependent-#{index}")
      end

      assigner = described_class.new(shard_count: 2, dependency_features: {})
      shard_1 = assigner.shard_formulae(dependent_formulae, shard_index: 1)
      shard_2 = assigner.shard_formulae(dependent_formulae, shard_index: 2)

      expect(shard_1 & shard_2).to eq([])
      expect((shard_1 + shard_2).sort_by(&:full_name))
        .to eq(dependent_formulae.sort_by(&:full_name))
    end

    it "deduplicates repeated dependent full names" do
      dependent_formulae = [
        instance_double(Formula, full_name: full_name("duplicate")),
        instance_double(Formula, full_name: full_name("duplicate")),
        instance_double(Formula, full_name: full_name("unique")),
      ]

      assigner = described_class.new(shard_count: 2, dependency_features: {})
      shards = (1..2).flat_map { |shard_index| assigner.shard_formulae(dependent_formulae, shard_index:) }

      expect(shards.map(&:full_name).sort).to eq([full_name("duplicate"), full_name("unique")])
    end

    it "keeps shard membership balanced for highly overlapping feature sets" do
      overlapping_formulae = (1..12).map { |index| "formula-#{index}" }
      dependency_features = overlapping_formulae.to_h do |formula_name|
        [full_name(formula_name), %w[shared-a shared-b shared-c]]
      end

      assigner = described_class.new(shard_count: 4, dependency_features:)
      shard_sizes = (1..4).map { |shard_index| assigner.shard_formulae(overlapping_formulae, shard_index:).length }

      expect(shard_sizes).to eq([3, 3, 3, 3])
    end
  end

  describe "argument validation" do
    it "raises for invalid shard counts" do
      expect do
        described_class.new(shard_count: 0, dependency_features: {})
      end.to raise_error(ArgumentError, /shard_count/)
    end

    it "raises for out-of-range shard indices" do
      assigner = described_class.new(shard_count: 2, dependency_features: {})

      expect do
        assigner.shard_formulae(formulae, shard_index: 3)
      end.to raise_error(ArgumentError, /shard_index/)
    end
  end
end
