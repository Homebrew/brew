# frozen_string_literal: true

require_relative "shared_examples"

RSpec.describe UnpackStrategy::Directory do
  let(:path) do
    mktmpdir.tap do |path|
      FileUtils.touch path/"file"
      FileUtils.ln_s "file", path/"symlink"
      FileUtils.ln path/"file", path/"hardlink"
      FileUtils.mkdir path/"folder"
      FileUtils.ln_s "folder", path/"folderSymlink"
    end
  end

  let(:unpack_dir) { mktmpdir }

  shared_examples "extract directory" do |move:|
    subject(:strategy) { described_class.new(path, move:) }

    it "does not follow symlinks" do
      strategy.extract(to: unpack_dir)
      expect(unpack_dir/"symlink").to be_a_symlink
    end

    it "does not follow top level symlinks to directories" do
      strategy.extract(to: unpack_dir)
      expect(unpack_dir/"folderSymlink").to be_a_symlink
    end

    it "preserves permissions of contained files" do
      FileUtils.chmod 0644, path/"file"

      strategy.extract(to: unpack_dir)
      expect((unpack_dir/"file").stat.mode & 0777).to eq 0644
    end

    it "preserves permissions of contained subdirectories" do
      FileUtils.mkdir unpack_dir/"folder"
      FileUtils.chmod 0755, unpack_dir/"folder"
      FileUtils.chmod 0700, path/"folder"

      strategy.extract(to: unpack_dir)
      expect((unpack_dir/"folder").stat.mode & 0777).to eq 0700
    end

    it "preserves permissions of the destination directory" do
      FileUtils.chmod 0700, path
      FileUtils.chmod 0755, unpack_dir

      strategy.extract(to: unpack_dir)
      expect(unpack_dir.stat.mode & 0777).to eq 0755
    end

    it "preserves mtime of contained files and directories" do
      FileUtils.mkdir unpack_dir/"folder"
      FileUtils.touch path/"folder", mtime: Time.utc(2000, 1, 2, 3, 4, 5, 678999), nocreate: true
      mtimes = path.children.to_h { |child| [child.basename, child.lstat.mtime] }

      strategy.extract(to: unpack_dir)
      expect(unpack_dir.children.to_h { |child| [child.basename, child.lstat.mtime] }).to eq mtimes
    end

    it "preserves unrelated destination files and subdirectories" do
      FileUtils.touch unpack_dir/"existing_file"
      FileUtils.mkdir unpack_dir/"existing_folder"

      strategy.extract(to: unpack_dir)
      expect(unpack_dir/"existing_file").to be_a_file
      expect(unpack_dir/"existing_folder").to be_a_directory
    end

    it "overwrites destination files/symlinks with source files/symlinks" do
      FileUtils.mkdir unpack_dir/"existing_folder"
      FileUtils.ln_s unpack_dir/"existing_folder", unpack_dir/"symlink"
      (unpack_dir/"file").write "existing contents"

      strategy.extract(to: unpack_dir)
      expect((unpack_dir/"file").read).to be_empty
      expect((unpack_dir/"symlink").readlink).to eq Pathname("file")
    end

    it "fails when overwriting a directory with a file" do
      FileUtils.mkdir unpack_dir/"file"
      expect { strategy.extract(to: unpack_dir) }.to raise_error(/Is a directory|cannot overwrite directory/i)
    end

    it "fails when overwriting a nested directory with a file" do
      FileUtils.touch path/"folder/nested"
      FileUtils.mkdir_p unpack_dir/"folder/nested"
      expect { strategy.extract(to: unpack_dir) }.to raise_error(/Is a directory|cannot overwrite directory/i)
    end
  end

  context "with `move: false`" do
    include_examples "extract directory", move: false
  end

  context "with `move: true`" do
    include_examples "extract directory", move: true

    it "preserves hardlinks" do
      strategy.extract(to: unpack_dir)
      expect((unpack_dir/"file").stat.ino).to eq (unpack_dir/"hardlink").stat.ino
    end

    # NOTE: We don't test `move: false` because system cp behaviour is inconsistent,
    # e.g. Ventura cp does not error but Sequoia and Linux cp will error
    it "fails when overwriting a file with a directory" do
      FileUtils.touch unpack_dir/"folder"
      expect { strategy.extract(to: unpack_dir) }.to raise_error(/cannot overwrite non-directory/i)
    end
  end
end
