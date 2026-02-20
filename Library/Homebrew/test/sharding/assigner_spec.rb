# frozen_string_literal: true

require "sharding/assigner"

RSpec.describe Homebrew::Sharding::Assigner do
  let(:item_ids) { %w[a b c d e f] }

  describe "#assignments" do
    it "deterministically assigns the same shard members" do
      features_by_item = item_ids.to_h { |item_id| [item_id, ["dep-#{item_id}"]] }

      assigner = described_class.new(shard_count: 3, features_by_item:)
      assignments_a = assigner.assignments(item_ids)
      assignments_b = assigner.assignments(item_ids)

      expect(assignments_a).to eq(assignments_b)
    end

    it "keeps cyclic nodes together when component size fits a shard" do
      features_by_item = item_ids.to_h { |item_id| [item_id, ["dep-#{item_id}"]] }
      adjacency_graph = {
        "a" => ["b"],
        "b" => ["a"],
      }

      assigner = described_class.new(shard_count: 2, features_by_item:, adjacency_graph:)
      assignments = assigner.assignments(item_ids)

      expect(assignments.fetch("a")).to eq(assignments.fetch("b"))
    end

    it "returns identical assignments for reordered and duplicated inputs" do
      features_by_item = item_ids.to_h { |item_id| [item_id, ["dep-#{item_id}"]] }

      assigner = described_class.new(shard_count: 3, features_by_item:)
      canonical_assignments = assigner.assignments(item_ids)
      reordered_assignments = assigner.assignments(%w[f e d c b a c a])

      expect(reordered_assignments).to eq(canonical_assignments)
      expect(reordered_assignments.keys.sort).to eq(item_ids.sort)
    end
  end

  describe "#shard_item_ids" do
    it "deduplicates repeated item IDs before sharding" do
      assigner = described_class.new(shard_count: 2, features_by_item: {})
      shards = (1..2).map { |shard_index| assigner.shard_item_ids(%w[a a b c c], shard_index:) }

      expect(shards.flatten.sort).to eq(%w[a b c])
      expect(shards.combination(2).all? do |first_shard, second_shard|
        !first_shard.intersect?(second_shard)
      end).to be(true)
    end

    it "assigns disjoint shards whose union matches the original set" do
      assigner = described_class.new(shard_count: 3, features_by_item: {})
      shards = (1..3).map { |shard_index| assigner.shard_item_ids(item_ids, shard_index:) }

      expect(shards.combination(2).all? do |first_shard, second_shard|
        !first_shard.intersect?(second_shard)
      end).to be(true)
      expect(shards.flatten.sort).to eq(item_ids.sort)
    end

    it "raises for out-of-range shard indices" do
      assigner = described_class.new(shard_count: 2, features_by_item: {})

      expect do
        assigner.shard_item_ids(item_ids, shard_index: 3)
      end.to raise_error(ArgumentError, /shard_index/)
    end
  end
end
