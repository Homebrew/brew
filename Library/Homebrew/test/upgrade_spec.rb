# frozen_string_literal: true

require "upgrade"

RSpec.describe Homebrew::Upgrade do
  describe ".build_dependency_graph" do
    let(:formulae) { [instance_double(Formula)] }
    let(:graph) { instance_double(Utils::TopologicalHash) }
    let(:tap) { instance_double(Tap, user: "test", repository: "tap") }

    it "returns the dependency graph when no tap errors occur" do
      allow(Utils::TopologicalHash).to receive(:graph_package_dependencies).with(formulae).and_return(graph)

      expect(described_class.send(:build_dependency_graph, formulae)).to eq(graph)
    end

    it "installs the tap and retries when a dependency's tap is not installed" do
      error = TapFormulaUnavailableError.new(tap, "formula")
      attempts = 0

      allow(tap).to receive(:installed?).and_return(false, true)
      expect(tap).to receive(:ensure_installed!)
      allow(Utils::TopologicalHash).to receive(:graph_package_dependencies).with(formulae) do
        attempts += 1
        raise error if attempts == 1

        graph
      end

      expect(described_class.send(:build_dependency_graph, formulae)).to eq(graph)
    end

    it "re-raises when the dependency's tap is already installed" do
      allow(tap).to receive(:installed?).and_return(true)
      error = TapFormulaUnavailableError.new(tap, "formula")

      allow(Utils::TopologicalHash).to receive(:graph_package_dependencies).with(formulae).and_raise(error)

      expect { described_class.send(:build_dependency_graph, formulae) }.to raise_error(TapFormulaUnavailableError)
    end

    it "re-raises when the tap cannot be installed" do
      allow(tap).to receive(:installed?).and_return(false)
      error = TapFormulaUnavailableError.new(tap, "formula")

      expect(tap).to receive(:ensure_installed!)
      allow(Utils::TopologicalHash).to receive(:graph_package_dependencies).with(formulae).and_raise(error)

      expect { described_class.send(:build_dependency_graph, formulae) }.to raise_error(TapFormulaUnavailableError)
    end
  end
end
