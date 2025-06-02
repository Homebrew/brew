# frozen_string_literal: true

require "lazy_object"

RSpec.describe LazyObject do
  describe "#initialize" do
    it "does not evaluate the block" do
      expect do |block|
        described_class.new(&block)
      end.not_to yield_control
    end
  end

  describe "when receiving a message" do
    it "evaluates the block" do
      expect(described_class.new { 42 }.to_s).to eq "42"
    end
  end

  describe "#!" do
    it "delegates to the underlying object" do
      expect(!(described_class.new { false })).to be true
    end
  end

  describe "#!=" do
    it "delegates to the underlying object" do
      expect(described_class.new { 42 }).not_to eq 13
    end
  end

  describe "#==" do
    it "delegates to the underlying object" do
      expect(described_class.new { 42 }).to eq 42
    end
  end
end
