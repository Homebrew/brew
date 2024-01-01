# frozen_string_literal: true

require "test/cask/dsl/shared_examples/base"

describe Cask::DSL::Container do
  subject(:container) { described_class.new(**params) }

  describe "#pairs" do
    let(:params) { { nested: "NestedApp.dmg" } }

    it "returns the attributes as a hash" do
      expect(container.pairs).to eq(nested: "NestedApp.dmg")
    end
  end

  describe "#to_s" do
    let(:params) { { nested: "NestedApp.dmg", type: :naked } }

    it "returns the stringified attributes" do
      expect(container.to_s).to eq('{:nested=>"NestedApp.dmg", :type=>:naked}')
    end
  end

  describe "#to_yaml" do
    let(:params) { { nested: "NestedApp.dmg", type: :naked } }

    it "returns the attributes in YAML format" do
      expect(container.to_yaml).to eq(<<~YAML)
        ---
        :nested: NestedApp.dmg
        :type: :naked
      YAML
    end
  end
end
