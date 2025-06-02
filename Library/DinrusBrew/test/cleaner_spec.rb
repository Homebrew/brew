# frozen_string_literal: true

require "cleaner"
require "formula"

RSpec.describe Cleaner do
  include FileUtils

  describe "#clean" do
    subject(:cleaner) { described_class.new(f) }

    let(:f) { formula("cleaner_test") { url "foo-1.0" } }

    before do
      f.prefix.mkpath
    end

    it "cleans files" do
      f.bin.mkpath
      f.lib.mkpath

      if OS.mac?
        cp "#{TEST_FIXTURE_DIR}/mach/a.out", f.bin
        cp Dir["#{TEST_FIXTURE_DIR}/mach/*.dylib"], f.lib
      elsif OS.linux?
        cp "#{TEST_FIXTURE_DIR}/elf/hello", f.bin
        cp Dir["#{TEST_FIXTURE_DIR}/elf/libhello.so.0"], f.lib
      end

      cleaner.clean

      if OS.mac?
        expect((f.bin/"a.out").stat.mode).to eq(0100555)
        expect((f.lib/"fat.dylib").stat.mode).to eq(0100444)
        expect((f.lib/"x86_64.dylib").stat.mode).to eq(0100444)
        expect((f.lib/"i386.dylib").stat.mode).to eq(0100444)
      elsif OS.linux?
        expect((f.bin/"hello").stat.mode).to eq(0100555)
        expect((f.lib/"libhello.so.0").stat.mode).to eq(0100555)
      end
    end

    it "prunes the prefix if it is empty" do
      cleaner.clean
      expect(f.prefix).not_to be_a_directory
    end

    it "prunes empty directories" do
      subdir = f.bin/"subdir"
      subdir.mkpath

      cleaner.clean

      expect(f.bin).not_to be_a_directory
      expect(subdir).not_to be_a_directory
    end

    it "removes a symlink when its target was pruned before" do
      dir = f.prefix/"b"
      symlink = f.prefix/"a"

      dir.mkpath
      ln_s dir.basename, symlink

      cleaner.clean

      expect(dir).not_to exist
      expect(symlink).not_to be_a_symlink
      expect(symlink).not_to exist
    end

    it "removes symlinks pointing to an empty directory" do
      dir = f.prefix/"b"
      symlink = f.prefix/"c"

      dir.mkpath
      ln_s dir.basename, symlink

      cleaner.clean

      expect(dir).not_to exist
      expect(symlink).not_to be_a_symlink
      expect(symlink).not_to exist
    end

    it "removes broken symlinks" do
      symlink = f.prefix/"symlink"
      ln_s "target", symlink

      cleaner.clean

      expect(symlink).not_to be_a_symlink
    end

    it "removes '.la' files" do
      file = f.lib/"foo.la"

      file.dirname.mkpath
      touch file

      cleaner.clean

      expect(file).not_to exist
    end

    it "removes 'perllocal' files" do
      file = f.lib/"perl5/darwin-thread-multi-2level/perllocal.pod"

      file.dirname.mkpath
      touch file

      cleaner.clean

      expect(file).not_to exist
    end

    it "removes '.packlist' files" do
      file = f.lib/"perl5/darwin-thread-multi-2level/auto/test/.packlist"

      file.dirname.mkpath
      touch file

      cleaner.clean

      expect(file).not_to exist
    end

    it "removes 'charset.alias' files" do
      file = f.lib/"charset.alias"

      file.dirname.mkpath
      touch file

      cleaner.clean

      expect(file).not_to exist
    end

    it "removes 'info/**/dir' files except for 'info/<name>/dir'" do
      file = f.info/"dir"
      arch_file = f.info/"i686-elf/dir"
      name_file = f.info/f.name/"dir"

      file.dirname.mkpath
      arch_file.dirname.mkpath
      name_file.dirname.mkpath

      touch file
      touch arch_file
      touch name_file

      cleaner.clean

      expect(file).not_to exist
      expect(arch_file).not_to exist
      expect(name_file).to exist
    end

    it "removes '*.dist-info/direct_url.json' files" do
      dir = f.lib/"python3.12/site-packages/test.dist-info"
      file = dir/"direct_url.json"
      unrelated_file = dir/"METADATA"
      unrelated_dir_file = f.lib/"direct_url.json"

      dir.mkpath
      touch file
      touch unrelated_file
      touch unrelated_dir_file

      cleaner.clean

      expect(file).not_to exist
      expect(unrelated_file).to exist
      expect(unrelated_dir_file).to exist
    end

    it "removes '*.dist-info/RECORD' files" do
      dir = f.lib/"python3.12/site-packages/test.dist-info"
      file = dir/"RECORD"
      unrelated_file = dir/"METADATA"
      unrelated_dir_file = f.lib/"RECORD"

      dir.mkpath
      touch file
      touch unrelated_file
      touch unrelated_dir_file

      cleaner.clean

      expect(file).not_to exist
      expect(unrelated_file).to exist
      expect(unrelated_dir_file).to exist
    end

    it "modifies '*.dist-info/INSTALLER' files" do
      file = f.lib/"python3.12/site-packages/test.dist-info/INSTALLER"
      file.dirname.mkpath
      file.write "pip\n"

      cleaner.clean

      expect(file.read).to eq "brew\n"
    end
  end

  describe "::skip_clean" do
    def stub_formula_skip_clean(skip_paths)
      formula("cleaner_test") do
        url "foo-1.0"

        skip_clean skip_paths
      end
    end

    it "adds paths that should be skipped" do
      f = stub_formula_skip_clean("bin")
      f.bin.mkpath

      described_class.new(f).clean

      expect(f.bin).to be_a_directory
    end

    it "also skips empty sub-directories under the added paths" do
      f = stub_formula_skip_clean("bin")
      subdir = f.bin/"subdir"
      subdir.mkpath

      described_class.new(f).clean

      expect(f.bin).to be_a_directory
      expect(subdir).to be_a_directory
    end

    it "allows skipping broken symlinks" do
      f = stub_formula_skip_clean("symlink")
      f.prefix.mkpath
      symlink = f.prefix/"symlink"
      ln_s "target", symlink

      described_class.new(f).clean

      expect(symlink).to be_a_symlink
    end

    it "allows skipping symlinks pointing to an empty directory" do
      f = stub_formula_skip_clean("c")
      dir = f.prefix/"b"
      symlink = f.prefix/"c"

      dir.mkpath
      ln_s dir.basename, symlink

      described_class.new(f).clean

      expect(dir).not_to exist
      expect(symlink).to be_a_symlink
      expect(symlink).not_to exist
    end

    it "allows skipping symlinks whose target was pruned before" do
      f = stub_formula_skip_clean("a")
      dir = f.prefix/"b"
      symlink = f.prefix/"a"

      dir.mkpath
      ln_s dir.basename, symlink

      described_class.new(f).clean

      expect(dir).not_to exist
      expect(symlink).to be_a_symlink
      expect(symlink).not_to exist
    end

    it "allows skipping '.la' files" do
      f = stub_formula_skip_clean(:la)

      file = f.lib/"foo.la"

      f.lib.mkpath
      touch file

      described_class.new(f).clean

      expect(file).to exist
    end

    it "allows skipping sub-directories" do
      f = stub_formula_skip_clean("lib/subdir")

      dir = f.lib/"subdir"

      dir.mkpath

      described_class.new(f).clean

      expect(dir).to be_a_directory
    end

    it "allows skipping paths relative to prefix" do
      f = stub_formula_skip_clean("bin/a")

      dir1 = f.bin/"a"
      dir2 = f.lib/"bin/a"

      dir1.mkpath
      dir2.mkpath

      described_class.new(f).clean

      expect(dir1).to exist
      expect(dir2).not_to exist
    end
  end
end
