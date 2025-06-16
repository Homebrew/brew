# frozen_string_literal: true

RSpec.describe OS::Linux::Elf do
  describe "::expand_elf_dst" do
    it "expands tokens that are not wrapped in curly braces" do
      str = "$ORIGIN/../lib"
      ref = "ORIGIN"
      repl = "/opt/homebrew/bin"
      expected = "/opt/homebrew/bin/../lib"
      expect(described_class.expand_elf_dst(str, ref, repl)).to eq(expected)
    end

    it "expands tokens that are wrapped in curly braces" do
      str = "${ORIGIN}/../lib"
      ref = "ORIGIN"
      repl = "/opt/homebrew/bin"
      expected = "/opt/homebrew/bin/../lib"
      expect(described_class.expand_elf_dst(str, ref, repl)).to eq(expected)

      str = "${ORIGIN}new/../lib"
      ref = "ORIGIN"
      repl = "/opt/homebrew/bin"
      expected = "/opt/homebrew/binnew/../lib"
      expect(described_class.expand_elf_dst(str, ref, repl)).to eq(expected)
    end

    it "expands multiple occurrences of token" do
      str = "${ORIGIN}/../..$ORIGIN/../lib"
      ref = "ORIGIN"
      repl = "/opt/homebrew/bin"
      expected = "/opt/homebrew/bin/../../opt/homebrew/bin/../lib"
      expect(described_class.expand_elf_dst(str, ref, repl)).to eq(expected)
    end

    it "rejects and passes through tokens containing additional characters" do
      str = "$ORIGINAL/../lib"
      ref = "ORIGIN"
      repl = "/opt/homebrew/bin"
      expected = "$ORIGINAL/../lib"
      expect(described_class.expand_elf_dst(str, ref, repl)).to eq(expected)

      str = "$ORIGIN_/../lib"
      ref = "ORIGIN"
      repl = "/opt/homebrew/bin"
      expected = "$ORIGIN_/../lib"
      expect(described_class.expand_elf_dst(str, ref, repl)).to eq(expected)

      str = "$ORIGIN_STORY/../lib"
      ref = "ORIGIN"
      repl = "/opt/homebrew/bin"
      expected = "$ORIGIN_STORY/../lib"
      expect(described_class.expand_elf_dst(str, ref, repl)).to eq(expected)

      str = "${ORIGINAL}/../lib"
      ref = "ORIGIN"
      repl = "/opt/homebrew/bin"
      expected = "${ORIGINAL}/../lib"
      expect(described_class.expand_elf_dst(str, ref, repl)).to eq(expected)

      str = "${ORIGIN_}/../lib"
      ref = "ORIGIN"
      repl = "/opt/homebrew/bin"
      expected = "${ORIGIN_}/../lib"
      expect(described_class.expand_elf_dst(str, ref, repl)).to eq(expected)

      str = "${ORIGIN_STORY}/../lib"
      ref = "ORIGIN"
      repl = "/opt/homebrew/bin"
      expected = "${ORIGIN_STORY}/../lib"
      expect(described_class.expand_elf_dst(str, ref, repl)).to eq(expected)
    end

    it "rejects and passes through tokens with mismatched curly braces" do
      str = "${ORIGIN/../lib"
      ref = "ORIGIN"
      repl = "/opt/homebrew/bin"
      expected = "${ORIGIN/../lib"
      expect(described_class.expand_elf_dst(str, ref, repl)).to eq(expected)

      str = "$ORIGIN}/../lib"
      ref = "ORIGIN"
      repl = "/opt/homebrew/bin"
      expected = "$ORIGIN}/../lib"
      expect(described_class.expand_elf_dst(str, ref, repl)).to eq(expected)
    end
  end
end
