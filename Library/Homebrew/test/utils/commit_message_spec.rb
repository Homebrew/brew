# frozen_string_literal: true

require "utils/commit_message"

RSpec.describe Utils::CommitMessage do
  describe ".normalize" do
    it "preserves a well-formatted message" do
      expect(described_class.normalize("foo: bar baz")).to eq("foo: bar baz")
    end

    it "adds colon-space separator" do
      expect(described_class.normalize("foo:bar")).to eq("foo: bar")
    end

    it "removes trailing period" do
      expect(described_class.normalize("foo: add 1.0 bottle.")).to eq("foo: add 1.0 bottle")
    end

    it "strips whitespace" do
      expect(described_class.normalize("  foo: bar  ")).to eq("foo: bar")
    end

    it "lowercases the action part" do
      expect(described_class.normalize("foo: Update URL")).to eq("foo: update url")
    end

    it "does not lowercase the name part" do
      expect(described_class.normalize("FooBar: update")).to eq("FooBar: update")
    end

    it "handles message without colon" do
      expect(described_class.normalize("foo 1.0")).to eq("foo 1.0")
    end

    it "handles trailing period and whitespace together" do
      expect(described_class.normalize("foo: add 1.0 bottle. ")).to eq("foo: add 1.0 bottle")
    end

    it "handles extra spaces around colon" do
      expect(described_class.normalize("foo :  bar")).to eq("foo: bar")
    end

    it "handles version in action part without lowercasing numbers" do
      expect(described_class.normalize("foo: 1.2.3")).to eq("foo: 1.2.3")
    end
  end
end
