# frozen_string_literal: true

require "extend/array"

describe Array do
  describe ".to_sentence" do
    it "converts a plain array to a sentence" do
      expect([].to_sentence).to eq("")
      expect(["one"].to_sentence).to eq("one")
      expect(["one", "two"].to_sentence).to eq("one and two")
      expect(["one", "two", "three"].to_sentence).to eq("one, two and three")
    end

    it "converts an array to a sentence with a custom connector" do
      expect(["one", "two", "three"].to_sentence(words_connector: " ")).to eq("one two and three")
      expect(["one", "two", "three"].to_sentence(words_connector: " & ")).to eq("one & two and three")
    end

    it "converts an array to a sentence with a custom last word connector" do
      expect(["one", "two", "three"].to_sentence(last_word_connector: ", and also "))
        .to eq("one, two, and also three")
      expect(["one", "two", "three"].to_sentence(last_word_connector: " ")).to eq("one, two three")
      expect(["one", "two", "three"].to_sentence(last_word_connector: " and ")).to eq("one, two and three")
    end

    it "converts an array to a sentence with a custom two word connector" do
      expect(["one", "two"].to_sentence(two_words_connector: " ")).to eq("one two")
    end

    it "creates a new string" do
      elements = ["one"]
      expect(elements.to_sentence.object_id).not_to eq(elements[0].object_id)
    end

    it "converts a non-String to a sentence" do
      expect([1].to_sentence).to eq("1")
    end

    it "converts an array with blank elements to a sentence" do
      expect([nil, "one", "", "two", "three"].to_sentence).to eq(", one, , two and three")
    end

    it "does not return a frozen string" do
      expect([""].to_sentence).not_to be_frozen
      expect(["one"].to_sentence).not_to be_frozen
      expect(["one", "two"].to_sentence).not_to be_frozen
      expect(["one", "two", "three"].to_sentence).not_to be_frozen
    end
  end
end
