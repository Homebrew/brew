# frozen_string_literal: true

require "extend/pathname"

describe Pathname do
  let(:elf_dir) { described_class.new "#{TEST_FIXTURE_DIR}/elf" }
  let(:sho) { elf_dir/"libforty.so.0" }
  let(:sho_without_runpath_rpath) { elf_dir/"libhello.so.0" }
  let(:exec) { elf_dir/"hello_with_rpath" }

  def patch_elfs
    mktmpdir do |tmp_dir|
      %w[c.elf].each do |elf|
        FileUtils.cp(elf_dir/elf, tmp_dir/elf)
        yield tmp_dir/elf
      end
    end
  end

  describe "#interpreter" do
    it "returns interpreter" do
      expect(exec.interpreter).to eq "/lib64/ld-linux-x86-64.so.2"
    end

    it "returns nil when absent" do
      expect(sho.interpreter).to be_nil
    end
  end

  describe "#rpath" do
    it "prefers runpath over rpath when both are present" do
      expect(sho.rpath).to eq "runpath"
    end

    it "returns runpath or rpath" do
      expect(exec.rpath).to eq "@@HOMEBREW_PREFIX@@/lib"
    end

    it "returns nil when absent" do
      expect(sho_without_runpath_rpath.rpath).to be_nil
    end
  end

  describe "#patch!" do
    let(:placeholder_prefix) { "@@HOMEBREW_PREFIX@@" }
    let(:short_prefix) { "/home/dwarf" }
    let(:standard_prefix) { "/home/linuxbrew/.linuxbrew" }
    let(:long_prefix) { "/home/organized/very organized/litter/more organized than/your words can describe" }
    let(:prefixes) { [short_prefix, standard_prefix, long_prefix] }

    # file is copied as modified_elf to avoid caching issues
    it "only interpreter" do
      prefixes.each do |new_prefix|
        patch_elfs do |elf|
          interpreter = elf.interpreter.gsub(placeholder_prefix, new_prefix)
          elf.patch!(interpreter: interpreter)

          modified_elf = elf.dirname/"mod.#{elf.basename}"
          FileUtils.cp(elf, modified_elf)
          expect(modified_elf.interpreter).to eq interpreter
          expect(modified_elf.rpath).to eq "@@HOMEBREW_PREFIX@@/lib"
        end
      end
    end

    it "only rpath" do
      prefixes.each do |new_prefix|
        patch_elfs do |elf|
          rpath = elf.rpath.gsub(placeholder_prefix, new_prefix)
          elf.patch!(rpath: rpath)

          modified_elf = elf.dirname/"mod.#{elf.basename}"
          FileUtils.cp(elf, modified_elf)
          expect(modified_elf.interpreter).to eq "@@HOMEBREW_PREFIX@@/lib/ld.so"
          expect(modified_elf.rpath).to eq rpath
        end
      end
    end

    it "both" do
      prefixes.each do |new_prefix|
        patch_elfs do |elf|
          interpreter = elf.interpreter.gsub(placeholder_prefix, new_prefix)
          rpath = elf.rpath.gsub(placeholder_prefix, new_prefix)
          elf.patch!(interpreter: interpreter, rpath: rpath)

          modified_elf = elf.dirname/"mod.#{elf.basename}"
          FileUtils.cp(elf, modified_elf)
          expect(modified_elf.interpreter).to eq interpreter
          expect(modified_elf.rpath).to eq rpath
        end
      end
    end
  end
end
