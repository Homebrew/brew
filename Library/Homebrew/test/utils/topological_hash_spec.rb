# frozen_string_literal: true

require "utils/topological_hash"

RSpec.describe Utils::TopologicalHash do
  describe "#tsort" do
    it "returns a topologically sorted array" do
      hash = described_class.new
      hash[1] = [2, 3]
      hash[2] = [3]
      hash[3] = []
      hash[4] = []
      expect(hash.tsort).to eq [3, 2, 1, 4]
    end
  end

  describe "#strongly_connected_components" do
    it "returns an array of arrays" do
      hash = described_class.new
      hash[1] = [2]
      hash[2] = [3, 4]
      hash[3] = [2]
      hash[4] = []
      expect(hash.strongly_connected_components).to eq [[4], [2, 3], [1]]
    end
  end

  describe "::graph_package_dependencies" do
    it "returns a topological hash" do
      formula1 = formula "homebrew-test-formula1" do
        url "foo"
        version "0.5"
      end

      formula2 = formula "homebrew-test-formula2" do
        url "foo"
        version "0.5"
        depends_on "homebrew-test-formula1"
      end

      formula3 = formula "homebrew-test-formula3" do
        url "foo"
        version "0.5"
        depends_on "homebrew-test-formula4"
      end

      formula4 = formula "homebrew-test-formula4" do
        url "foo"
        version "0.5"
        depends_on "homebrew-test-formula3"
      end

      cask1 = Cask::Cask.new("homebrew-test-cask1") do
        url "foo"
        version "1.2.3"
      end

      cask2 = Cask::Cask.new("homebrew-test-cask2") do
        url "foo"
        version "1.2.3"
        depends_on cask: "homebrew-test-cask1"
        depends_on formula: "homebrew-test-formula1"
      end

      cask3 = Cask::Cask.new("homebrew-test-cask3") do
        url "foo"
        version "1.2.3"
        depends_on cask: "homebrew-test-cask2"
      end

      stub_formula_loader formula1
      stub_formula_loader formula2
      stub_formula_loader formula3
      stub_formula_loader formula4

      stub_cask_loader cask1
      stub_cask_loader cask2
      stub_cask_loader cask3

      packages = [formula1, formula2, formula3, formula4, cask1, cask2, cask3]
      expect(described_class.graph_package_dependencies(packages)).to eq({
        formula1 => [],
        formula2 => [formula1],
        formula3 => [formula4],
        formula4 => [formula3],
        cask1    => [],
        cask2    => [formula1, cask1],
        cask3    => [cask2],
      })

      sorted = [formula1, cask1, cask2, cask3, formula2]
      expect(described_class.graph_package_dependencies([cask3, cask2, cask1, formula2, formula1]).tsort).to eq sorted
      expect(described_class.graph_package_dependencies([cask3, formula2]).tsort).to eq sorted

      expect { described_class.graph_package_dependencies([formula3, formula4]).tsort }.to raise_error TSort::Cyclic
    end
  end
end
