# typed: strict
# frozen_string_literal: true

require "utils/text"

RSpec.describe Utils::Text do
  describe ".to_sentence" do
    specify do
      expect(described_class.to_sentence([])).to eq("")
      expect(described_class.to_sentence(["one"])).to eq("one")
      expect(described_class.to_sentence(["one", "two"])).to eq("one and two")
      expect(described_class.to_sentence(["one", "two", "three"])).to eq("one, two and three")
      expect(described_class.to_sentence([1])).to eq("1")
      expect(described_class.to_sentence([nil, "one", "", "two", "three"])).to eq(", one, , two and three")
      expect(described_class.to_sentence(["one", "two", "three"], conjunction: "or")).to eq("one, two or three")
      expect(described_class.to_sentence([""])).not_to be_frozen
      expect(described_class.to_sentence(["one"])).not_to be_frozen
      expect(described_class.to_sentence(["one", "two"])).not_to be_frozen
      expect(described_class.to_sentence(["one", "two", "three"])).not_to be_frozen
    end

    it "creates a new string" do
      elements = ["one"]
      expect(described_class.to_sentence(elements).object_id).not_to eq(elements[0].object_id)
    end
  end
end
