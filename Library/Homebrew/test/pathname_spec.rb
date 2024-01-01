# frozen_string_literal: true

require "extend/pathname"
require "install_renamed"

describe Pathname do
  include FileUtils

  let(:src) { mktmpdir }
  let(:dst) { mktmpdir }
  let(:file) { src/"foo" }
  let(:dir) { src/"bar" }

  describe DiskUsageExtension do
    before do
      mkdir_p dir/"a-directory"
      touch [dir/".DS_Store", dir/"a-file"]
      File.truncate(dir/"a-file", 1_048_576)
      ln_s dir/"a-file", dir/"a-symlink"
      ln dir/"a-file", dir/"a-hardlink"
    end

    describe "#file_count" do
      it "returns the number of files in a directory" do
        expect(dir.file_count).to eq(3)
      end
    end

    describe "#abv" do
      context "when called on a directory" do
        it "returns a string with the file count and disk usage" do
          expect(dir.abv).to eq("3 files, 1MB")
        end
      end

      context "when called on a file" do
        it "returns the disk usage" do
          expect((dir/"a-file").abv).to eq("1MB")
        end
      end
    end
  end

  describe "#rmdir_if_possible" do
    before { mkdir_p dir }

    it "returns true and removes a directory if it doesn't contain files" do
      expect(dir.rmdir_if_possible).to be true
      expect(dir).not_to exist
    end

    it "returns false and doesn't delete a directory if it contains files" do
      touch dir/"foo"
      expect(dir.rmdir_if_possible).to be false
      expect(dir).to be_a_directory
    end

    it "ignores .DS_Store files" do
      touch dir/".DS_Store"
      expect(dir.rmdir_if_possible).to be true
      expect(dir).not_to exist
    end
  end

  describe "#append_lines" do
    it "appends lines to a file" do
      touch file

      file.append_lines("CONTENT")
      expect(File.read(file)).to eq <<~EOS
        CONTENT
      EOS

      file.append_lines("CONTENTS")
      expect(File.read(file)).to eq <<~EOS
        CONTENT
        CONTENTS
      EOS
    end

    it "raises an error if the file does not exist" do
      expect(file).not_to exist
      expect { file.append_lines("CONTENT") }.to raise_error(RuntimeError)
    end
  end

  describe "#atomic_write" do
    it "atomically replaces a file" do
      touch file
      file.atomic_write("CONTENT")
      expect(File.read(file)).to eq("CONTENT")
    end

    it "preserves permissions" do
      File.open(file, "w", 0100777) do
        # do nothing
      end
      file.atomic_write("CONTENT")
      expect(file.stat.mode.to_s(8)).to eq((~File.umask & 0100777).to_s(8))
    end

    it "preserves default permissions" do
      file.atomic_write("CONTENT")
      sentinel = file.dirname.join("sentinel")
      touch sentinel
      expect(file.stat.mode.to_s(8)).to eq(sentinel.stat.mode.to_s(8))
    end
  end

  describe "#ensure_writable" do
    it "makes a file writable and restores permissions afterwards" do
      skip "User is root so everything is writable." if Process.euid.zero?
      touch file
      chmod 0555, file
      expect(file).not_to be_writable
      file.ensure_writable do
        expect(file).to be_writable
      end
      expect(file).not_to be_writable
    end
  end

  describe "#extname" do
    it "supports common multi-level archives" do
      expect(described_class.new("foo-0.1.tar.gz").extname).to eq(".tar.gz")
      expect(described_class.new("foo-0.1.cpio.gz").extname).to eq(".cpio.gz")
    end

    it "does not treat version numbers as extensions" do
      expect(described_class.new("foo-0.1").extname).to eq("")
      expect(described_class.new("foo-1.0-rc1").extname).to eq("")
      expect(described_class.new("foo-1.2.3").extname).to eq ""
    end

    it "supports `.7z` with version numbers" do
      expect(described_class.new("snap7-full-1.4.2.7z").extname).to eq ".7z"
    end
  end

  describe "#stem" do
    it "returns the basename without double extensions" do
      expect(Pathname("foo-0.1.tar.gz").stem).to eq("foo-0.1")
      expect(Pathname("foo-0.1.cpio.gz").stem).to eq("foo-0.1")
    end
  end

  describe "#install" do
    before do
      (src/"a.txt").write "This is sample file a."
      (src/"b.txt").write "This is sample file b."
    end

    it "raises an error if the file doesn't exist" do
      expect { dst.install "non_existent_file" }.to raise_error(Errno::ENOENT)
    end

    it "installs a file to a directory with its basename" do
      touch file
      dst.install(file)
      expect(dst/file.basename).to exist
      expect(file).not_to exist
    end

    it "creates intermediate directories" do
      touch file
      expect(dir).not_to be_a_directory
      dir.install(file)
      expect(dir).to be_a_directory
    end

    it "can install a file" do
      dst.install src/"a.txt"
      expect(dst/"a.txt").to exist, "a.txt was not installed"
      expect(dst/"b.txt").not_to exist, "b.txt was installed."
    end

    it "can install an array of files" do
      dst.install [src/"a.txt", src/"b.txt"]

      expect(dst/"a.txt").to exist, "a.txt was not installed"
      expect(dst/"b.txt").to exist, "b.txt was not installed"
    end

    it "can install a directory" do
      bin = src/"bin"
      bin.mkpath
      mv Dir[src/"*.txt"], bin
      dst.install bin

      expect(dst/"bin/a.txt").to exist, "a.txt was not installed"
      expect(dst/"bin/b.txt").to exist, "b.txt was not installed"
    end

    it "supports renaming files" do
      dst.install src/"a.txt" => "c.txt"

      expect(dst/"c.txt").to exist, "c.txt was not installed"
      expect(dst/"a.txt").not_to exist, "a.txt was installed but not renamed"
      expect(dst/"b.txt").not_to exist, "b.txt was installed"
    end

    it "supports renaming multiple files" do
      dst.install(src/"a.txt" => "c.txt", src/"b.txt" => "d.txt")

      expect(dst/"c.txt").to exist, "c.txt was not installed"
      expect(dst/"d.txt").to exist, "d.txt was not installed"
      expect(dst/"a.txt").not_to exist, "a.txt was installed but not renamed"
      expect(dst/"b.txt").not_to exist, "b.txt was installed but not renamed"
    end

    it "supports renaming directories" do
      bin = src/"bin"
      bin.mkpath
      mv Dir[src/"*.txt"], bin
      dst.install bin => "libexec"

      expect(dst/"bin").not_to exist, "bin was installed but not renamed"
      expect(dst/"libexec/a.txt").to exist, "a.txt was not installed"
      expect(dst/"libexec/b.txt").to exist, "b.txt was not installed"
    end

    it "can install directories as relative symlinks" do
      bin = src/"bin"
      bin.mkpath
      mv Dir[src/"*.txt"], bin
      dst.install_symlink bin

      expect(dst/"bin").to be_a_symlink
      expect(dst/"bin").to be_a_directory
      expect(dst/"bin/a.txt").to exist
      expect(dst/"bin/b.txt").to exist
      expect((dst/"bin").readlink).to be_relative
    end

    it "can install relative paths as symlinks" do
      dst.install_symlink "foo" => "bar"
      expect((dst/"bar").readlink).to eq(described_class.new("foo"))
    end

    it "can install relative symlinks in a symlinked directory" do
      mkdir_p dst/"1/2"
      dst.install_symlink "1/2" => "12"
      expect((dst/"12").readlink).to eq(described_class.new("1/2"))
      (dst/"12").install_symlink dst/"foo"
      expect((dst/"12/foo").readlink).to eq(described_class.new("../../foo"))
    end
  end

  describe InstallRenamed do
    before do
      dst.extend(described_class)
    end

    it "renames the installed file if it already exists" do
      file.write "a"
      dst.install file

      file.write "b"
      dst.install file

      expect(File.read(dst/file.basename)).to eq("a")
      expect(File.read(dst/"#{file.basename}.default")).to eq("b")
    end

    it "renames the installed directory" do
      file.write "a"
      dst.install src
      expect(File.read(dst/src.basename/file.basename)).to eq("a")
    end

    it "recursively renames directories" do
      (dst/dir.basename).mkpath
      (dst/dir.basename/"another_file").write "a"
      dir.mkpath
      (dir/"another_file").write "b"
      dst.install dir
      expect(File.read(dst/dir.basename/"another_file.default")).to eq("b")
    end
  end

  describe "#cp_path_sub" do
    it "copies a file and replaces the given pattern" do
      file.write "a"
      file.cp_path_sub src, dst
      expect(File.read(dst/file.basename)).to eq("a")
    end

    it "copies a directory and replaces the given pattern" do
      dir.mkpath
      dir.cp_path_sub src, dst
      expect(dst/dir.basename).to be_a_directory
    end
  end

  describe "#ds_store?" do
    it "returns whether a file is .DS_Store or not" do
      expect(file).not_to be_ds_store
      expect(file/".DS_Store").to be_ds_store
    end
  end
end
