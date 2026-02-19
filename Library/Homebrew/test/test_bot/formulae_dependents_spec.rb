# frozen_string_literal: true

require "test_bot"

RSpec.describe Homebrew::TestBot::FormulaeDependents do
  subject(:formulae_dependents) do
    described_class.new(tap: nil, git: nil, dry_run: false, fail_fast: false, verbose: false)
  end

  let(:formulae) { %w[alpha beta gamma delta epsilon zeta] }
  let(:args_class) { Struct.new(:dependent_shard_count, :dependent_shard_index) }

  before do
    allow(Formulary).to receive(:factory) do |formula_name|
      instance_double(Formula, full_name: "homebrew/core/#{formula_name}")
    end
  end

  define_method(:shard_args) do |count, index|
    instance_double(args_class, dependent_shard_count: count.to_s, dependent_shard_index: index.to_s)
  end

  define_method(:full_name) do |formula_name|
    "homebrew/core/#{formula_name}"
  end

  describe "#sharded_dependent_testing_formulae" do
    it "deterministically assigns the same shard members" do
      dependency_features = formulae.to_h do |formula_name|
        [full_name(formula_name), ["dep-#{formula_name}"]]
      end

      shard_a = formulae_dependents.send(
        :sharded_dependent_testing_formulae,
        formulae,
        args:                shard_args(3, 2),
        dependency_features:,
      )
      shard_b = formulae_dependents.send(
        :sharded_dependent_testing_formulae,
        formulae,
        args:                shard_args(3, 2),
        dependency_features:,
      )

      expect(shard_a).to eq(shard_b)
    end

    it "assigns disjoint shards whose union matches the original set" do
      shards = (1..3).map do |shard_index|
        formulae_dependents.send(
          :sharded_dependent_testing_formulae,
          formulae,
          args: shard_args(3, shard_index),
        )
      end

      expect(shards.combination(2).all? do |first_shard, second_shard|
        !first_shard.intersect?(second_shard)
      end).to be(true)
      expect(shards.flatten.sort).to eq(formulae.sort)
    end

    it "preserves existing behavior when shard count is one" do
      sharded_formulae = formulae_dependents.send(:sharded_dependent_testing_formulae, formulae,
                                                  args: shard_args(1, 1))

      expect(sharded_formulae).to eq(formulae)
    end

    it "handles empty dependent sets" do
      sharded_formulae = formulae_dependents.send(:sharded_dependent_testing_formulae, [], args: shard_args(4, 1))

      expect(sharded_formulae).to eq([])
    end

    it "shards dependent formula objects by full_name" do
      dependent_formulae = (1..20).map do |index|
        instance_double(Formula, full_name: "homebrew/core/dependent-#{index}")
      end

      shard_1 = formulae_dependents.send(:sharded_dependent_testing_formulae, dependent_formulae,
                                         args: shard_args(2, 1))
      shard_2 = formulae_dependents.send(:sharded_dependent_testing_formulae, dependent_formulae,
                                         args: shard_args(2, 2))

      expect(shard_1 & shard_2).to eq([])
      expect((shard_1 + shard_2).sort_by(&:full_name))
        .to eq(dependent_formulae.sort_by(&:full_name))
    end
  end
end
