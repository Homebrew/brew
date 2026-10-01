# typed: true
# frozen_string_literal: true

require "keg_relocate"
require "patchelf"
require "elftools"

RSpec.describe Keg do
  let(:dir) { HOMEBREW_CELLAR/"foo/1.0.0" }
  let(:file) { dir/"bin/program" }
  let(:baked_rpath) { "#{dir}/lib/#{"deep/" * 10}end" }

  def patch_rpath(rpath)
    patcher = PatchELF::Patcher.new(file.to_s, on_error: :silent)
    patcher.rpath = rpath
    patcher.save(patchelf_compatible: true)
  end

  def patch_interpreter(interpreter)
    patcher = PatchELF::Patcher.new(file.to_s, on_error: :silent)
    patcher.interpreter = interpreter
    patcher.save(patchelf_compatible: true)
  end

  before do
    Pathname(baked_rpath).mkpath
    file.dirname.mkpath
    FileUtils.cp TEST_FIXTURE_DIR/"elf/hello", file
    patch_rpath baked_rpath
  end

  describe "::text_matches_in_file" do
    it "keeps prefix strings the dynamic loader still references" do
      expect(described_class.text_matches_in_file(file, dir.to_s, [], [], nil).size).to eq 1
    end

    it "drops dead loader strings nothing references any more" do
      # Shrinking the RPATH leaves an in-place `X` run inside `.dynstr`;
      # writing a prefix string over it recreates the dead bytes a moved or
      # rewritten string table leaves behind.
      patch_rpath "#{Keg::PREFIX_PLACEHOLDER}/lib"
      corpse_offset = File.binread(file).index("X" * (dir.to_s.length + 2))
      raise "no X padding run found" if corpse_offset.nil?

      File.open(file, "r+b") do |f|
        f.seek(corpse_offset)
        f.write("#{dir}\x00")
      end

      expect(described_class.text_matches_in_file(file, dir.to_s, [], [], nil)).to be_empty
    end

    it "drops prefix strings outside every section" do
      patch_rpath "#{Keg::PREFIX_PLACEHOLDER}/lib"
      file.open("ab") { |f| f.write("\x00#{dir}\x00") }

      expect(described_class.text_matches_in_file(file, dir.to_s, [], [], nil)).to be_empty
    end

    it "drops prefixes before the substring a dynamic tag references" do
      # Point DT_RPATH into the interior of the baked string, as a linker
      # does for tail-merged entries: the prefix bytes before the
      # referenced substring are then dead.
      value_offset = file.open("rb") do |stream|
        dynamic = ELFTools::ELFFile.new(stream).segment_by_type(:dynamic)
        index = dynamic.tags.find_index do |tag|
          [ELFTools::Constants::DT::DT_RPATH, ELFTools::Constants::DT::DT_RUNPATH].include?(tag.header.d_tag.to_i)
        end
        dynamic.header.p_offset.to_i + (index * 16) + 8
      end
      referenced = File.binread(file, 8, value_offset).unpack1("Q<")
      File.open(file, "r+b") do |f|
        f.seek(value_offset)
        f.write([referenced + dir.to_s.length + 1].pack("Q<"))
      end

      expect(described_class.text_matches_in_file(file, dir.to_s, [], [], nil)).to be_empty
    end

    it "keeps matches when the section-name table is unavailable" do
      # `e_shstrndx` may legally be `SHN_UNDEF`, leaving sections unnameable.
      File.open(file, "r+b") do |f|
        f.seek(62)
        f.write("\x00\x00")
      end

      expect(described_class.text_matches_in_file(file, dir.to_s, [], [], nil).size).to eq 1
    end

    it "keeps the interpreter the loader still uses" do
      interpreter = "#{dir}/ld.so"
      FileUtils.touch interpreter
      patch_rpath "#{Keg::PREFIX_PLACEHOLDER}/lib"
      patch_interpreter interpreter

      expect(described_class.text_matches_in_file(file, dir.to_s, [], [], nil).size).to eq 1
    end

    it "drops old interpreter bytes the loader no longer uses" do
      patch_rpath "#{Keg::PREFIX_PLACEHOLDER}/lib"
      # Growing the interpreter moves it; shrinking it back leaves an
      # in-place padding run where dead interpreter bytes can survive.
      patch_interpreter "#{dir}/#{"deep/" * 10}ld.so"
      patch_interpreter "#{Keg::PREFIX_PLACEHOLDER}/lib/ld.so"
      anchor = "#{Keg::PREFIX_PLACEHOLDER}/lib/ld.so\x00"
      corpse_offset = File.binread(file).index(anchor)
      raise "no placeholdered interpreter found" if corpse_offset.nil?

      File.open(file, "r+b") do |f|
        f.seek(corpse_offset + anchor.bytesize)
        f.write("#{dir}\x00")
      end

      expect(described_class.text_matches_in_file(file, dir.to_s, [], [], nil)).to be_empty
    end

    it "keeps matches in files whose ELF tables are truncated" do
      file.binwrite "\x7fELF\x02\x01\x01#{"\x00" * 9}\x00#{dir}\x00"

      expect(described_class.text_matches_in_file(file, dir.to_s, [], [], nil).size).to eq 1
    end

    it "keeps prefix strings compiled into ordinary sections" do
      patch_rpath "#{Keg::PREFIX_PLACEHOLDER}/lib"
      text_offset = file.open("rb") do |stream|
        ELFTools::ELFFile.new(stream).section_by_name(".text").header.sh_offset.to_i
      end
      File.open(file, "r+b") do |f|
        f.seek(text_offset)
        f.write("\x00#{dir}\x00")
      end

      expect(described_class.text_matches_in_file(file, dir.to_s, [], [], nil).size).to eq 1
    end
  end
end
