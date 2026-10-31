# typed: true
# frozen_string_literal: true

require "extend/pathname"

RSpec.describe Pathname do
  let(:elf_dir) { ELFPathname.wrap("#{TEST_FIXTURE_DIR}/elf") }
  let(:sho) { ELFPathname.wrap(elf_dir/"libforty.so.0") }
  let(:sho_without_runpath_rpath) { ELFPathname.wrap(elf_dir/"libhello.so.0") }
  let(:exec) { ELFPathname.wrap(elf_dir/"hello_with_rpath") }
  let(:static_pie) { ELFPathname.wrap(elf_dir/"static_pie") }

  def patch_elfs
    mktmpdir do |tmp_dir|
      %w[c.elf].each do |elf|
        FileUtils.cp(elf_dir/elf, tmp_dir/elf)
        yield ELFPathname.wrap(tmp_dir/elf)
      end
    end
  end

  describe "#interpreter" do
    it "returns interpreter" do
      expect(exec.interpreter).to eq "/lib64/ld-linux-x86-64.so.2"
      expect(sho.interpreter).to be_nil
    end
  end

  describe "#pie?" do
    context "with a static position-independent executable" do
      it "is true" do
        expect(static_pie.pie?).to be true
      end
    end

    context "with an executable that lacks the flag" do
      it "is false" do
        expect(exec.pie?).to be false
      end
    end
  end

  describe "#rpath" do
    it "returns rpath" do
      expect(sho.rpath).to eq "runpath"
      expect(exec.rpath).to eq "@@HOMEBREW_PREFIX@@/lib"
      expect(sho_without_runpath_rpath.rpath).to be_nil
    end
  end

  describe "#section_names" do
    it "returns section names" do
      expect(exec.section_names).to include(".dynamic")
    end
  end

  describe "metadata" do
    it "is read without patchelf.rb" do
      expect(exec).not_to receive(:patchelf_patcher)
      exec.rpath
    end

    it "is read with patchelf.rb when the header can't hold the program header count" do
      mktmpdir do |tmp_dir|
        path = tmp_dir/exec.basename
        FileUtils.cp(exec, path)
        program_header_count_offset = 0x38
        program_header_count_in_first_section = 0xffff
        File.binwrite(path, [program_header_count_in_first_section].pack("v"), program_header_count_offset)
        elf = ELFPathname.wrap(path)
        expect(elf).to receive(:patchelf_patcher).and_call_original
        elf.rpath
      end
    end

    it "is read from a 32-bit little-endian library" do
      lib = ELFPathname.wrap(elf_dir/"libx_arm32.so.2")
      expect([lib.dylib_id, lib.rpath, lib.dynamically_linked_libraries])
        .to eq ["libx.so.2", "/opt/a/lib:$ORIGIN/../lib", ["libdep.so.1"]]
    end

    it "is read from a 64-bit big-endian executable" do
      exe = ELFPathname.wrap(elf_dir/"exe_s390x")
      expect([exe.interpreter, exe.rpath, exe.pie?]).to eq ["/lib/ld-test-loader.so.1", "/opt/exe/lib", true]
    end

    it "reads a file without program headers as not dynamic" do
      expect(ELFPathname.wrap(elf_dir/"static_no_phdrs").dynamic_elf?).to be false
    end
  end

  describe "#patch!" do
    let(:placeholder_prefix) { "@@HOMEBREW_PREFIX@@" }
    let(:short_prefix) { "/home/dwarf" }
    let(:standard_prefix) { "/home/linuxbrew/.linuxbrew" }
    let(:long_prefix) { "/home/organized/very organized/litter/more organized than/your words can describe" }
    let(:prefixes) { [short_prefix, standard_prefix, long_prefix].map { |prefix| ELFPathname.wrap(prefix) } }

    it "does not evaluate the patcher signature at runtime" do
      expect(T::Utils.signature_for_instance_method(ELFShim, :patchelf_patcher)).to be_nil
    end

    # file is copied as modified_elf to avoid caching issues
    it "only interpreter" do
      prefixes.each do |new_prefix|
        patch_elfs do |elf|
          interpreter = elf.interpreter.gsub(placeholder_prefix, new_prefix)
          elf.patch!(interpreter:)

          modified_elf = ELFPathname.wrap(elf.dirname/"mod.#{elf.basename}")
          FileUtils.cp(elf, modified_elf.to_path)
          expect(modified_elf.interpreter).to eq interpreter
          expect(modified_elf.rpath).to eq "@@HOMEBREW_PREFIX@@/lib"
        end
      end
    end

    it "only rpath" do
      prefixes.each do |new_prefix|
        patch_elfs do |elf|
          rpath = elf.rpath.gsub(placeholder_prefix, new_prefix)
          elf.patch!(rpath:)

          modified_elf = ELFPathname.wrap(elf.dirname/"mod.#{elf.basename}")
          FileUtils.cp(elf, modified_elf.to_path)
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
          elf.patch!(interpreter:, rpath:)

          modified_elf = ELFPathname.wrap(elf.dirname/"mod.#{elf.basename}")
          FileUtils.cp(elf, modified_elf.to_path)
          expect(modified_elf.interpreter).to eq interpreter
          expect(modified_elf.rpath).to eq rpath
        end
      end
    end
  end
end
