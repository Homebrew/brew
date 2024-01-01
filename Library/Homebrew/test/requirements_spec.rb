# frozen_string_literal: true

require "requirements"

describe Requirements do
  subject(:requirements) { described_class.new }

  describe "#<<" do
    it "returns itself" do
      expect(requirements << Object.new).to be(requirements)
    end

    it "merges duplicate requirements" do
      klass = Class.new(Requirement)
      requirements << klass.new << klass.new
      expect(requirements.count).to eq(1)
    end
  end
end
