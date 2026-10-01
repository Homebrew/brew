# typed: strict
# frozen_string_literal: true

require "cask/token_generator"

RSpec.describe Cask::TokenGenerator do
  describe "::generate" do
    it "generates a token from a simple app name" do
      expect(described_class.generate("Example App.app")).to eq "example"
    end

    it "removes platform designations" do
      expect(described_class.generate("Software for Mac.app")).to eq "software"
    end

    it "removes release qualifiers" do
      expect(described_class.generate("Software Beta.app")).to eq "software"
    end

    it "keeps a trailing term joined to the name" do
      expect(described_class.generate("WhatsApp.app")).to eq "whatsapp"
    end

    it "keeps digits that may be part of the name" do
      expect(described_class.generate("iTerm2.app")).to eq "iterm2"
    end

    it "keeps the hyphen before a digit" do
      expect(described_class.generate("Physics 101.app")).to eq "physics-101"
    end

    it "removes trailing hardware designations" do
      expect(described_class.generate("Software ARM64.app")).to eq "software"
    end

    it "hyphenates multi-word names" do
      expect(described_class.generate("Fancy Word Processor")).to eq "fancy-word-processor"
    end

    it "spells out symbols" do
      expect(described_class.generate("Notes+")).to eq "notes-plus"
    end

    it "converts underscores to hyphens" do
      expect(described_class.generate("Fancy_Word")).to eq "fancy-word"
    end

    it "converts middots to hyphens" do
      expect(described_class.generate("Foo·Bar")).to eq "foo-bar"
    end
  end

  describe "::warnings" do
    it "warns about digits in tokens" do
      expect(described_class.warnings("app2")).not_to be_empty
    end

    it "does not warn about digits in an @ suffix" do
      expect(described_class.warnings("app@7")).to be_empty
    end
  end
end
