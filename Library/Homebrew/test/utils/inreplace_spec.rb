# typed: true
# frozen_string_literal: true

require "tempfile"
require "utils/inreplace"

RSpec.describe Utils::Inreplace do
  let(:file) { Tempfile.new("test") }

  before do
    File.binwrite(file, <<~EOS)
      a
      b
      c
      aa
    EOS
  end

  after { file.unlink }

  describe ".inreplace" do
    it "raises error if there are no files given to replace" do
      expect do
        described_class.inreplace [], "d", "f"
      end.to raise_error(Utils::Inreplace::Error)
    end

    it "raises error if there is nothing to replace" do
      expect do
        described_class.inreplace file.path, "d", "f"
      end.to raise_error(Utils::Inreplace::Error)
    end

    it "raises error if there is nothing to replace in block form" do
      expect do
        described_class.inreplace(file.path) do |s|
          # Using `gsub!` here is what we want, and it's only a test.
          s.gsub!("d", "f") # rubocop:disable Performance/StringReplacement
        end
      end.to raise_error(Utils::Inreplace::Error)
    end

    it "raises error if there is no make variables to replace" do
      expect do
        described_class.inreplace(file.path) do |s|
          s.change_make_var! "VAR", "value"
          s.remove_make_var! "VAR2"
        end
      end.to raise_error(Utils::Inreplace::Error)
    end

    it "substitutes pathname within file" do
      # For a specific instance of this, see https://github.com/Homebrew/homebrew-core/blob/a8b0b10/Formula/loki.rb#L48
      described_class.inreplace(file.path) do |s|
        s.gsub!(Pathname("b"), Pathname("f"))
      end
      expect(File.binread(file)).to eq <<~EOS
        a
        f
        c
        aa
      EOS
    end

    it "substitutes all occurrences within file when `global: true`" do
      described_class.inreplace(file.path, "a", "foo")
      expect(File.binread(file)).to eq <<~EOS
        foo
        b
        c
        foofoo
      EOS
    end

    it "substitutes only the first occurrence when `global: false`" do
      described_class.inreplace(file.path, "a", "foo", global: false)
      expect(File.binread(file)).to eq <<~EOS
        foo
        b
        c
        aa
      EOS
    end
  end
end
