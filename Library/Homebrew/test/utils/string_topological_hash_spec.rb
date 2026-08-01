# typed: false
# frozen_string_literal: true

require "utils/topological_hash"

RSpec.describe Utils::StringTopologicalHash do
  it "treats an edge to a missing node as a leaf" do
    topo = described_class.new
    topo["a"] = ["b"]
    topo["b"] = ["libice"]

    expect(topo.tsort).to eq(["libice", "b", "a"])
  end

  describe "#sorted_names" do
    it "orders dependencies before their dependents" do
      topo = described_class.new
      topo["a"] = ["b"]
      topo["b"] = []

      expect(topo.sorted_names { nil }).to eq(["b", "a"])
    end

    it "flattens a cyclic graph via strongly connected components without raising" do
      topo = described_class.new
      topo["a"] = ["b"]
      topo["b"] = ["a"]

      cycles = []
      expect(topo.sorted_names { |c| cycles.concat(c) }).to contain_exactly("a", "b")
      expect(cycles).to eq([["a", "b"]])
    end
  end
end
