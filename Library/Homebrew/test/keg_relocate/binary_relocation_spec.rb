# typed: true
# frozen_string_literal: true

require "keg_relocate"

RSpec.describe Keg do
  subject(:keg) { described_class.new(HOMEBREW_CELLAR/"foo/1.0.0") }

  let(:dir) { HOMEBREW_CELLAR/"foo/1.0.0" }
  let(:newdir) { HOMEBREW_CELLAR/"foo" }
  let(:binary_file) { dir/"file.bin" }

  before do
    dir.mkpath
    allow(keg).to receive(:codesign_patched_binaries)
  end

  def setup_binary_file
    binary_file.atomic_write <<~EOS
      \x00#{dir}\x00
    EOS
  end

  describe "#relocate_build_prefix" do
    specify "replace prefix in binary files" do
      setup_binary_file

      keg.relocate_build_prefix(keg, dir, newdir)

      old_prefix_matches = Set.new
      keg.each_unique_file_matching(dir) do |file|
        old_prefix_matches << file
      end

      expect(old_prefix_matches.size).to eq 0

      new_prefix_matches = Set.new
      keg.each_unique_file_matching(newdir) do |file|
        new_prefix_matches << file
      end

      expect(new_prefix_matches.size).to eq 1
    end

    specify "replace prefix in recorded files without scanning the keg" do
      setup_binary_file

      expect(keg).not_to receive(:each_unique_file_matching)
      keg.relocate_build_prefix(keg, dir, newdir, files: [Pathname("file.bin")])

      null_padding = "\x00" * (dir.to_s.length - newdir.to_s.length)
      expect(binary_file.binread).to eq "\x00#{newdir}#{null_padding}\x00\n"
    end

    specify "replaces every occurrence in every string" do
      binary_file.atomic_write "\x00#{dir}/a:#{dir}/b\x00#{dir}/c\x00"

      keg.relocate_build_prefix(keg, dir, newdir)

      null_padding = "\x00" * (dir.to_s.length - newdir.to_s.length)
      expect(binary_file.binread)
        .to eq "\x00#{newdir}/a:#{newdir}/b#{null_padding * 2}\x00#{newdir}/c#{null_padding}\x00"
    end

    specify "patches hardlinks once and keeps them linked" do
      setup_binary_file
      hardlink = dir/"hardlink.bin"
      FileUtils.ln binary_file, hardlink

      patched = keg.relocate_build_prefix(keg, dir, newdir)

      expect(patched).to contain_exactly(Pathname("file.bin"), Pathname("hardlink.bin"))
      expect(hardlink.stat.ino).to eq binary_file.stat.ino
      expect(hardlink.binread).to include newdir.to_s
    end

    specify "leaves sharballs untouched" do
      binary_file.atomic_write "#!/bin/sh\n\x00#{dir}\x00"

      keg.relocate_build_prefix(keg, dir, newdir)

      expect(binary_file.binread).to include dir.to_s
    end

    specify "refuses a longer prefix before touching any file" do
      setup_binary_file
      original = binary_file.binread

      expect { keg.relocate_build_prefix(keg, newdir, dir) }.to raise_error(ArgumentError, /longer/)
      expect(binary_file.binread).to eq original
    end

    specify "re-signs patched files" do
      setup_binary_file

      expect(keg).to receive(:codesign_patched_binaries).with([binary_file])

      keg.relocate_build_prefix(keg, dir, newdir)
    end

    specify "keeps suffix-merged references into ELF string tables valid" do
      require "patchelf"
      require "elftools"

      elf = dir/"program"
      FileUtils.cp TEST_FIXTURE_DIR/"elf/hello", elf
      patcher = PatchELF::Patcher.new(elf.to_s, on_error: :silent)
      patcher.rpath = "#{dir}/lib/x"
      patcher.save(patchelf_compatible: true)
      # Point DT_RPATH into the interior `lib/x`, as a tail-merging linker does.
      value_offset = elf.open("rb") do |stream|
        dynamic = ELFTools::ELFFile.new(stream).segment_by_type(:dynamic)
        index = dynamic.tags.find_index { |tag| tag.header.d_tag.to_i == ELFTools::Constants::DT::DT_RPATH }
        dynamic.header.p_offset.to_i + (index * 16) + 8
      end
      referenced = File.binread(elf, 8, value_offset).unpack1("Q<")
      File.open(elf, "r+b") do |f|
        f.seek(value_offset)
        f.write([referenced + dir.to_s.length + 1].pack("Q<"))
      end
      suffix_offset = elf.binread.index("#{dir}/lib/x") + dir.to_s.length + 1

      keg.relocate_build_prefix(keg, dir, newdir, files: [Pathname("program")])

      separators = "/" * (dir.to_s.length - newdir.to_s.length + 1)
      expect(elf.binread).to include "#{newdir}#{separators}lib/x\x00"
      expect(File.binread(elf, 6, suffix_offset)).to eq "lib/x\x00"
    end

    specify "does not rewrite recorded files without the old prefix" do
      binary_file.atomic_write "\x00unrelated\x00"
      inode = binary_file.stat.ino

      keg.relocate_build_prefix(keg, dir, newdir, files: [Pathname("file.bin")])

      expect(binary_file.stat.ino).to eq inode
    end
  end
end
