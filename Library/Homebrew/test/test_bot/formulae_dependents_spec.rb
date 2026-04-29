# typed: false
# frozen_string_literal: true

require "dev-cmd/test-bot"

RSpec.describe Homebrew::TestBot::FormulaeDependents do
  subject(:formulae_dependents) do
    described_class.new(tap: nil, git: "git", dry_run: true, fail_fast: false, verbose: false)
  end

  let(:args) { double(skip_recursive_dependents?: false) }

  describe "#configure_dependent_sharding!" do
    before do
      formulae_dependents.instance_variable_set(:@dependent_testing_formulae, %w[testball testball-user])
      allow(Formulary).to receive(:factory).with("testball").and_return(instance_double(Formula))
      allow(Formulary).to receive(:factory).with("testball-user").and_return(instance_double(Formula))
      allow(formulae_dependents).to receive(:skip_recursive_dependents_for).and_return(false)
      allow(formulae_dependents).to receive(:dependent_formula_names)
        .with("testball", skip_recursive_dependents: false)
        .and_return(%w[alpha shared])
      allow(formulae_dependents).to receive(:dependent_formula_names)
        .with("testball-user", skip_recursive_dependents: false)
        .and_return(%w[beta shared])
    end

    it "deduplicates shared dependents across testing formulae before sharding" do
      with_env(
        "HOMEBREW_DEPS_SHARD_INDEX" => "0",
        "HOMEBREW_DEPS_SHARD_TOTAL" => "2",
      ) do
        formulae_dependents.send(:configure_dependent_sharding!, args:)
      end

      expect(formulae_dependents.instance_variable_get(:@assigned_dependent_formula_names))
        .to eq(Set.new(%w[alpha shared]))
    end

    it "assigns dependents across shards without duplicates" do
      shard_zero = described_class.new(tap: nil, git: "git", dry_run: true, fail_fast: false, verbose: false)
      shard_one = described_class.new(tap: nil, git: "git", dry_run: true, fail_fast: false, verbose: false)

      [shard_zero, shard_one].each do |deps|
        deps.instance_variable_set(:@dependent_testing_formulae, %w[testball testball-user])
        allow(deps).to receive(:skip_recursive_dependents_for).and_return(false)
        allow(Formulary).to receive(:factory).with("testball").and_return(instance_double(Formula))
        allow(Formulary).to receive(:factory).with("testball-user").and_return(instance_double(Formula))
        allow(deps).to receive(:dependent_formula_names)
          .with("testball", skip_recursive_dependents: false)
          .and_return(%w[alpha gamma epsilon])
        allow(deps).to receive(:dependent_formula_names)
          .with("testball-user", skip_recursive_dependents: false)
          .and_return(%w[beta delta])
      end

      with_env("HOMEBREW_DEPS_SHARD_INDEX" => "0", "HOMEBREW_DEPS_SHARD_TOTAL" => "2") do
        shard_zero.send(:configure_dependent_sharding!, args:)
      end
      with_env("HOMEBREW_DEPS_SHARD_INDEX" => "1", "HOMEBREW_DEPS_SHARD_TOTAL" => "2") do
        shard_one.send(:configure_dependent_sharding!, args:)
      end

      assigned_zero = shard_zero.instance_variable_get(:@assigned_dependent_formula_names)
      assigned_one = shard_one.instance_variable_get(:@assigned_dependent_formula_names)

      expect(assigned_zero | assigned_one).to eq(Set.new(%w[alpha beta delta epsilon gamma]))
      expect(assigned_zero & assigned_one).to eq(Set.new)
      expect(assigned_zero.count - assigned_one.count).to be <= 1
    end

    it "preserves existing behavior for a single shard" do
      dependent = instance_double(Formula, full_name: "alpha")
      formulae_dependents.instance_variable_set(:@handled_dependent_formula_names, Set["alpha"])

      with_env("HOMEBREW_DEPS_SHARD_TOTAL" => "1") do
        formulae_dependents.send(:configure_dependent_sharding!, args:)
      end

      expect(formulae_dependents.instance_variable_get(:@assigned_dependent_formula_names)).to be_nil
      expect(formulae_dependents.instance_variable_get(:@handled_dependent_formula_names)).to eq(Set.new)
      expect(formulae_dependents.send(:sharded_dependents, [dependent])).to eq([dependent])
    end

    it "tests a shared dependent once when multiple changed formulae reach it on the same shard" do
      alpha = instance_double(Formula, full_name: "alpha")
      shared = instance_double(Formula, full_name: "shared")

      with_env(
        "HOMEBREW_DEPS_SHARD_INDEX" => "0",
        "HOMEBREW_DEPS_SHARD_TOTAL" => "2",
      ) do
        formulae_dependents.send(:configure_dependent_sharding!, args:)
      end

      first_formula_dependents = formulae_dependents.send(:sharded_dependents, [alpha, shared])
      first_formula_dependents.each do |dependent|
        formulae_dependents.instance_variable_get(:@handled_dependent_formula_names).add(dependent.full_name)
      end

      expect(first_formula_dependents).to eq([alpha, shared])
      expect(formulae_dependents.send(:sharded_dependents, [shared])).to eq([])
    end
  end
end
