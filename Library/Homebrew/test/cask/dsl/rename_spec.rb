# frozen_string_literal: true

RSpec.describe Cask::DSL::Rename do
  subject(:rename) { described_class.new(from, to) }

  let(:from) { "Source File*.pkg" }
  let(:to) { "Target File.pkg" }

  describe "#initialize" do
    it "sets the from and to attributes" do
      expect(rename.from).to eq("Source File*.pkg")
      expect(rename.to).to eq("Target File.pkg")
    end
  end

  describe "#pairs" do
    it "returns the attributes as a hash" do
      expect(rename.pairs).to eq(from: "Source File*.pkg", to: "Target File.pkg")
    end
  end

  describe "#to_s" do
    it "returns the stringified attributes" do
      expect(rename.to_s).to eq(rename.pairs.inspect)
    end
  end

  describe "#perform_rename" do
    let(:tmpdir) { mktmpdir }
    let(:staged_path) { Pathname(tmpdir) }

    context "when staged_path does not exist" do
      let(:staged_path) { Pathname("/nonexistent/path") }

      it "does nothing" do
        expect { rename.perform_rename(staged_path) }.not_to raise_error
      end
    end

    context "when using glob patterns" do
      let(:from) { "Test App*.pkg" }
      let(:to) { "Test App.pkg" }

      before do
        (staged_path / "Test App v1.2.3.pkg").write("test content")
        (staged_path / "Test App v2.0.0.pkg").write("other content")
      end

      it "renames the first matching file" do
        rename.perform_rename(staged_path)

        expect(staged_path / "Test App.pkg").to exist
        expect((staged_path / "Test App.pkg").read).to eq("test content")
        expect(staged_path / "Test App v1.2.3.pkg").not_to exist
        expect(staged_path / "Test App v2.0.0.pkg").to exist
      end
    end

    context "when using exact filenames" do
      let(:from) { "Exact File.dmg" }
      let(:to) { "New Name.dmg" }

      before do
        (staged_path / "Exact File.dmg").write("dmg content")
      end

      it "renames the exact file" do
        rename.perform_rename(staged_path)

        expect(staged_path / "New Name.dmg").to exist
        expect((staged_path / "New Name.dmg").read).to eq("dmg content")
        expect(staged_path / "Exact File.dmg").not_to exist
      end
    end

    context "when target is in a subdirectory" do
      let(:from) { "source.txt" }
      let(:to) { "subdir/target.txt" }

      before do
        (staged_path / "source.txt").write("content")
      end

      it "creates the subdirectory and renames the file" do
        rename.perform_rename(staged_path)

        expect(staged_path / "subdir" / "target.txt").to exist
        expect((staged_path / "subdir" / "target.txt").read).to eq("content")
        expect(staged_path / "source.txt").not_to exist
      end
    end

    context "when no files match the pattern" do
      let(:from) { "nonexistent*.pkg" }
      let(:to) { "target.pkg" }

      it "does nothing" do
        rename.perform_rename(staged_path)

        expect(staged_path / "target.pkg").not_to exist
      end
    end

    context "when source file doesn't exist after glob" do
      let(:from) { "missing.txt" }
      let(:to) { "target.txt" }

      it "does nothing" do
        expect { rename.perform_rename(staged_path) }.not_to raise_error
        expect(staged_path / "target.txt").not_to exist
      end
    end
  end
end
