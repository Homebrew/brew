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

    it "preserves existing behavior when shard index is missing" do
      args = instance_double(args_class, dependent_shard_count: "4", dependent_shard_index: nil)
      sharded_formulae = formulae_dependents.send(:sharded_dependent_testing_formulae, formulae, args:)

      expect(sharded_formulae).to eq(formulae)
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

    it "deduplicates repeated dependent full names before sharding" do
      dependent_formulae = [
        instance_double(Formula, full_name: full_name("duplicate")),
        instance_double(Formula, full_name: full_name("duplicate")),
        instance_double(Formula, full_name: full_name("unique")),
      ]

      shard_1 = formulae_dependents.send(:sharded_dependent_testing_formulae, dependent_formulae,
                                         args: shard_args(2, 1))
      shard_2 = formulae_dependents.send(:sharded_dependent_testing_formulae, dependent_formulae,
                                         args: shard_args(2, 2))

      expect((shard_1 + shard_2).map(&:full_name).sort).to eq([full_name("duplicate"), full_name("unique")])
    end
  end

  describe "#dependents_for_formula" do
    let(:dependents_args_class) do
      Struct.new(
        :skip_recursive_dependents?,
        :build_dependents_from_source?,
        :dependent_shard_count,
        :dependent_shard_index,
      )
    end

    let(:args) do
      instance_double(
        dependents_args_class,
        skip_recursive_dependents?:    true,
        build_dependents_from_source?: false,
        dependent_shard_count:         "2",
        dependent_shard_index:         "1",
      )
    end

    it "builds dependency features and graph for sharding and filters dependents by shard membership" do
      formulae_dependents.instance_variable_set(:@tested_formulae, [])
      formulae_dependents.instance_variable_set(:@dependent_testing_formulae, [])
      formulae_dependents.instance_variable_set(:@testing_formulae_with_tested_dependents, [])

      root_formula = instance_double(Formula, full_name: full_name("root"))

      dep_on_root = instance_double(
        Dependency,
        implicit?:  false,
        optional?:  false,
        build?:     false,
        test?:      false,
        to_formula: root_formula,
      )
      dep_on_two = instance_double(
        Dependency,
        implicit?:  false,
        optional?:  false,
        build?:     false,
        test?:      false,
        to_formula: nil,
      )
      dep_two_formula = instance_double(
        Formula,
        full_name:     full_name("dep-two"),
        deps:          [dep_on_root],
        test_defined?: false,
      )
      allow(dep_on_two).to receive(:to_formula).and_return(dep_two_formula)
      dep_one_formula = instance_double(
        Formula,
        full_name:     full_name("dep-one"),
        deps:          [dep_on_root, dep_on_two],
        test_defined?: true,
      )

      allow(Formulary).to receive(:factory) do |formula_name|
        case formula_name
        when "dep-one"
          dep_one_formula
        when "dep-two"
          dep_two_formula
        else
          instance_double(Formula, full_name: "homebrew/core/#{formula_name}")
        end
      end
      allow(Utils).to receive(:safe_popen_read).and_return("dep-one\ndep-two\n", "")
      allow(formulae_dependents).to receive(:bottled?).and_return(true)
      allow(formulae_dependents).to receive(:info_header)
      allow(OS).to receive(:linux?).and_return(false)

      captured = {}
      allow(formulae_dependents).to receive(:sharded_dependent_testing_formulae) do |formulae_arg,
                                                                                      args:,
                                                                                      dependency_features:,
                                                                                      dependency_graph:|
        captured[:formulae] = formulae_arg
        captured[:args] = args
        captured[:dependency_features] = dependency_features
        captured[:dependency_graph] = dependency_graph
        [dep_one_formula]
      end

      source_dependents, bottled_dependents, testable_dependents = formulae_dependents.send(
        :dependents_for_formula,
        root_formula,
        "root",
        args:,
      )

      expect(captured[:args]).to eq(args)
      expect(captured[:formulae]).to contain_exactly(dep_one_formula, dep_two_formula)
      expect(captured[:dependency_features]).to eq(
        full_name("dep-one") => [full_name("dep-two"), full_name("root")],
        full_name("dep-two") => [full_name("root")],
      )
      expect(captured[:dependency_graph]).to eq(
        full_name("dep-one") => [full_name("dep-two")],
        full_name("dep-two") => [],
      )

      expect(source_dependents).to eq([])
      expect(bottled_dependents).to eq([dep_one_formula])
      expect(testable_dependents).to eq([dep_one_formula])
    end
  end
end
