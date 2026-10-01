# typed: true
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

    context "when checking rename paths" do
      let(:staged_path) { (tmpdir/"staged").tap(&:mkpath) }
      let(:from) { "source.pkg" }
      let(:to) { "target.pkg" }

      before do
        (staged_path/"source.pkg").write("staged content")
        (tmpdir/"source.pkg").write("other content")
      end

      it "rejects an absolute source path" do
        expect do
          described_class.new((tmpdir/"source.pkg").to_s, to).perform_rename(staged_path)
        end.to raise_error(ArgumentError, /within the staged cask/)
      end

      it "rejects an absolute target path" do
        expect do
          described_class.new(from, (tmpdir/"source.pkg").to_s).perform_rename(staged_path)
        end.to raise_error(ArgumentError, /within the staged cask/)
      end

      it "rejects a source path with a parent component" do
        expect do
          described_class.new("../source.pkg", to).perform_rename(staged_path)
        end.to raise_error(ArgumentError, /within the staged cask/)
      end

      it "rejects a target path with a parent component" do
        expect do
          described_class.new(from, "../source.pkg").perform_rename(staged_path)
        end.to raise_error(ArgumentError, /within the staged cask/)
      end

      context "with a symlinked source directory" do
        let(:from) { "linked/source.pkg" }

        before { (staged_path/"linked").make_symlink(tmpdir) }

        it "rejects the path" do
          expect { rename.perform_rename(staged_path) }.to raise_error(ArgumentError, /symlink/)
        end
      end

      context "with a symlinked target directory" do
        let(:to) { "linked/source.pkg" }

        before { (staged_path/"linked").make_symlink(tmpdir) }

        it "rejects the path" do
          expect { rename.perform_rename(staged_path) }.to raise_error(ArgumentError, /symlink/)
        end
      end

      context "with a glob expanding to a parent directory" do
        let(:from) { "{..,unused}/*.pkg" }

        it "rejects the match" do
          expect { rename.perform_rename(staged_path) }.to raise_error(ArgumentError, /within the staged cask/)
        end
      end

      context "with a glob matching a symlinked directory" do
        let(:from) { "link*/*.pkg" }

        before { (staged_path/"linked").make_symlink(tmpdir) }

        it "rejects the match" do
          expect { rename.perform_rename(staged_path) }.to raise_error(ArgumentError, /symlink/)
        end
      end

      context "with a symlink above a new target directory" do
        let(:to) { "linked/new/target.pkg" }

        before { (staged_path/"linked").make_symlink(tmpdir) }

        it "rejects the path before creating the directory" do
          expect { rename.perform_rename(staged_path) }.to raise_error(ArgumentError, /symlink/)
        end
      end
    end
  end
end
