# typed: true
# frozen_string_literal: true

require "utils/output"

require "extend/pathname"
require "install_renamed"

RSpec.describe Pathname do
  let(:src) { mktmpdir }
  let(:dst) { mktmpdir }
  let(:file) { src/"foo" }
  let(:dir) { src/"bar" }

  include FileUtils

  describe EagerInitializeExtension do
    it "defines the lazy memoised ivars on every new Pathname" do
      pathname = Pathname.new(file.to_s)
      [:@disk_usage, :@file_count].each do |ivar|
        expect(pathname.instance_variable_defined?(ivar)).to be(true), "expected #{ivar} to be defined"
        # Read the raw ivars: the names are dynamic and eager raw definition is under test.
        # rubocop:disable Homebrew/NoInstanceVariableAccessInTests
        expect(pathname.instance_variable_get(ivar)).to be_nil
        # rubocop:enable Homebrew/NoInstanceVariableAccessInTests
      end
    end
  end

  describe DiskUsageExtension do
    before do
      mkdir_p dir/"a-directory"
      touch [dir/".DS_Store", dir/"a-file"]
      File.truncate(dir/"a-file", 1_048_576)
      ln_s dir/"a-file", dir/"a-symlink"
      ln_s dir/"a-directory", dir/"a-directory-symlink"
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
    it "deprecates the Pathname helper" do
      expect(Utils::Output).to receive(:odeprecated)
        .with("Pathname#rmdir_if_possible", "Utils::Path.rmdir_if_possible")
      expect(Utils::Path).to receive(:rmdir_if_possible).with(dir).and_return(true)

      expect(dir.rmdir_if_possible).to be(true)
    end
  end

  describe "#cp_path_sub" do
    it "deprecates the Pathname helper" do
      expect(Utils::Output).to receive(:odeprecated)
        .with("Pathname#cp_path_sub", "Utils::Path.cp_path_sub")
      expect(Utils::Path).to receive(:cp_path_sub).with(file, src, dst)

      file.cp_path_sub(src, dst)
    end
  end

  describe "#install_info" do
    it "deprecates the Pathname helper" do
      expect(Utils::Output).to receive(:odeprecated)
        .with("Pathname#install_info", "Utils::Path.install_info")
      expect(Utils::Path).to receive(:install_info).with(file)

      file.install_info
    end
  end

  describe "#uninstall_info" do
    it "deprecates the Pathname helper" do
      expect(Utils::Output).to receive(:odeprecated)
        .with("Pathname#uninstall_info", "Utils::Path.uninstall_info")
      expect(Utils::Path).to receive(:uninstall_info).with(file)

      file.uninstall_info
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
    it "deprecates the Pathname helper" do
      expect(Utils::Output).to receive(:odeprecated)
        .with("Pathname#ensure_writable", "Utils::Path.ensure_writable")
      expect(Utils::Path).to receive(:ensure_writable).with(file).and_yield

      file.ensure_writable { nil }
    end
  end

  describe "#text_executable?" do
    it "deprecates the Pathname helper" do
      expect(Utils::Output).to receive(:odeprecated)
        .with("Pathname#text_executable?", "Utils::Path.text_executable?")
      expect(Utils::Path).to receive(:text_executable?).with(file).and_return(true)

      expect(file.text_executable?).to be(true)
    end
  end

  describe "#resolved_path" do
    it "deprecates the Pathname helper" do
      expect(Utils::Output).to receive(:odeprecated)
        .with("Pathname#resolved_path", "Utils::Path.resolved_path")
      expect(Utils::Path).to receive(:resolved_path).with(file).and_return(file)

      expect(file.resolved_path).to eq(file)
    end
  end

  describe "#resolved_path_exists?" do
    it "deprecates the Pathname helper" do
      expect(Utils::Output).to receive(:odeprecated)
        .with("Pathname#resolved_path_exists?", "Utils::Path.resolved_path_exists?")
      expect(Utils::Path).to receive(:resolved_path_exists?).with(file).and_return(true)

      expect(file.resolved_path_exists?).to be(true)
    end
  end

  describe "#extname" do
    specify do
      expect(described_class.new("foo-0.1.tar.gz").extname).to eq(".tar.gz")
      expect(described_class.new("foo-0.1.cpio.gz").extname).to eq(".cpio.gz")
      expect(described_class.new("foo-0.1").extname).to eq("")
      expect(described_class.new("foo-1.0-rc1").extname).to eq("")
      expect(described_class.new("foo-1.2.3").extname).to eq ""
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
      dst.install(src/"a.txt" => "c.txt", src/"b.txt" => Pathname("d.txt"))

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
      dst.install_symlink "foo" => Pathname("bar"), "baz" => "qux"
      expect((dst/"bar").readlink).to eq(described_class.new("foo"))
      expect((dst/"qux").readlink).to eq(described_class.new("baz"))
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

  describe "#ds_store?" do
    it "does not extend Pathname with a Finder metadata predicate" do
      expect(file).not_to respond_to(:ds_store?)
    end
  end

  it "does not extend Pathname with archive inspection methods" do
    expect([:magic_number, :file_type, :zipinfo].select { |method| file.respond_to?(method) }).to be_empty
  end
end
