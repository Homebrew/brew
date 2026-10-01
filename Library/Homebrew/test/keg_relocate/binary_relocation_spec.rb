# typed: true
# frozen_string_literal: true

require "keg_relocate"

RSpec.describe Keg do
  subject(:keg) { described_class.new(HOMEBREW_CELLAR/"foo/1.0.0") }

  let(:dir) { HOMEBREW_CELLAR/"foo/1.0.0" }
  let(:newdir) { HOMEBREW_CELLAR/"foo" }
  let(:padded_prefix) { "#{newdir}#{"/" * (dir.to_s.bytesize - newdir.to_s.bytesize)}" }
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

    specify "replace prefix in recorded files" do
      setup_binary_file

      keg.relocate_build_prefix(keg, dir, newdir, files: [Pathname("file.bin")])

      expect(binary_file.binread).to eq "\x00#{padded_prefix}\x00\n"
    end

    context "with an x86-64 prefix split across movabs instructions" do
      let(:old_prefix) { "/home/linuxbrew/.linuxbrew" }
      let(:new_prefix) { "/home/u/.b" }
      let(:instructions) do
        "\x48\xb9/home/li\x48\x8b\x6c\x24\x08\x48\x89\x08" \
        "\x48\xb9nuxbrew/\x48\x89\x48\x08" \
        "\x48\xb9.linuxbr\x48\x89\x48\x10" \
        "\x48\xb9ew/etc/f\x4c\x8b\x65\x00\x48\x89\x48\x18" \
        "\x48\xb9c/fonts\x00\x48\x89\x48\x1d".b
      end
      let(:text_offset) do
        binary_file.open("rb") do |stream|
          ELFTools::ELFFile.new(stream).section_by_name(".text").header.sh_offset.to_i
        end
      end
      let(:relocated_instructions) do
        instructions.sub("/home/li", "/home/u/").sub("nuxbrew/", ".b//////")
                    .sub(".linuxbr", "////////").sub("ew/etc/f", "///etc/f")
      end

      before do
        require "elftools"

        FileUtils.cp TEST_FIXTURE_DIR/"elf/hello", binary_file
        binary_file.open("r+b") do |file|
          file.seek(text_offset)
          file.write(instructions)
        end
      end

      it "relocates instruction operands without changing other bytes" do
        original = binary_file.binread

        keg.relocate_build_prefix(keg, old_prefix, new_prefix)

        expect(binary_file.binread).to eq original.sub(instructions, relocated_instructions)
      end

      it "finds split prefixes missing from older bottle metadata" do
        original = binary_file.binread

        keg.relocate_build_prefix(keg, old_prefix, new_prefix, files: [])

        expect(binary_file.binread).to eq original.sub(instructions, relocated_instructions)
      end

      it "preserves hardlinks and relocates both contiguous and split prefixes" do
        binary_file.open("ab") { |file| file.write("\x00#{old_prefix}/etc/fonts\x00") }
        FileUtils.ln binary_file, dir/"hardlink.bin"
        original = binary_file.binread

        patched = keg.relocate_build_prefix(keg, old_prefix, new_prefix, files: [Pathname("file.bin")])

        expect(patched).to contain_exactly(Pathname("file.bin"), Pathname("hardlink.bin"))
        expect((dir/"hardlink.bin").stat.ino).to eq binary_file.stat.ino
        expect(binary_file.binread).to eq original.sub(instructions, relocated_instructions)
                                                  .sub(old_prefix, new_prefix.ljust(old_prefix.bytesize, "/"))
      end

      it "relocates operands using extended registers" do
        original = binary_file.binread.gsub("\x48\xb9".b, "\x49\xbf".b)
        binary = original.dup

        described_class.replace_x86_64_prefix!(binary, old_prefix, new_prefix)

        expect(binary).to eq original.sub(instructions.gsub("\x48\xb9".b, "\x49\xbf".b),
                                          relocated_instructions.gsub("\x48\xb9".b, "\x49\xbf".b))
      end

      it "does not skip intervening movabs operands" do
        binary_file.open("r+b") do |file|
          file.seek(text_offset)
          file.write(instructions.sub("nuxbrew/", "ignored!\x48\xb9nuxbrew/".b))
        end
        original = binary_file.binread

        keg.relocate_build_prefix(keg, old_prefix, new_prefix)

        expect(binary_file.binread).to eq original
      end

      it "leaves incomplete prefixes untouched" do
        binary_file.binwrite binary_file.binread.sub(".linuxbr", ".otherbr")
        original = binary_file.binread

        keg.relocate_build_prefix(keg, old_prefix, new_prefix)

        expect(binary_file.binread).to eq original
      end

      it "leaves non-path prefixes untouched" do
        binary_file.binwrite binary_file.binread.sub("ew/etc/f", "ew-extra")
        original = binary_file.binread

        keg.relocate_build_prefix(keg, old_prefix, new_prefix)

        expect(binary_file.binread).to eq original
      end

      it "leaves other ELF architectures untouched" do
        binary_file.open("r+b") do |file|
          file.seek(18)
          file.write("\xb7\x00".b)
        end
        original = binary_file.binread

        keg.relocate_build_prefix(keg, old_prefix, new_prefix)

        expect(binary_file.binread).to eq original
      end

      it "leaves instruction-like bytes outside executable sections untouched" do
        binary_file.open("r+b") do |file|
          file.seek(text_offset)
          file.write("\x00" * instructions.bytesize)
        end
        binary_file.open("ab") { |file| file.write(instructions) }
        original = binary_file.binread

        keg.relocate_build_prefix(keg, old_prefix, new_prefix)

        expect(binary_file.binread).to eq original
      end
    end

    specify "replaces every occurrence in every string" do
      binary_file.atomic_write "\x00#{dir}/a:#{dir}/b\x00#{dir}/c\x00"

      keg.relocate_build_prefix(keg, dir, newdir)

      expect(binary_file.binread)
        .to eq "\x00#{padded_prefix}/a:#{padded_prefix}/b\x00#{padded_prefix}/c\x00"
    end

    specify "keeps module paths read using compiled-in lengths usable" do
      module_path = "#{dir}/opt/perl/lib/perl5/5.44"
      binary_file.atomic_write "\x00#{module_path}\x00"
      (newdir/"opt/perl/lib/perl5/5.44").mkpath
      (newdir/"opt/perl/lib/perl5/5.44/strict.pm").write "1;\n"

      keg.relocate_build_prefix(keg, dir, newdir)

      expect(File.read("#{File.binread(binary_file, module_path.bytesize, 1)}/strict.pm")).to eq "1;\n"
    end

    specify "replaces an equal-length prefix without padding" do
      binary_file.atomic_write "\x00#{dir}/lib\x00suffix\x00"
      new_prefix = newdir.to_s.ljust(dir.to_s.bytesize, "x")

      keg.relocate_build_prefix(keg, dir, new_prefix)

      expect(binary_file.binread).to eq "\x00#{new_prefix}/lib\x00suffix\x00"
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

    specify "patches every name of a hardlinked file recorded once in metadata" do
      setup_binary_file
      hardlink = dir/"hardlink.bin"
      FileUtils.ln binary_file, hardlink

      patched = keg.relocate_build_prefix(keg, dir, newdir, files: [Pathname("file.bin")])

      expect(patched).to contain_exactly(Pathname("file.bin"), Pathname("hardlink.bin"))
      expect(hardlink.stat.ino).to eq binary_file.stat.ino
      expect(hardlink.binread).to include newdir.to_s
    end

    specify "ignores recorded paths that escape the keg" do
      outside = dir.parent/"escape.bin"
      outside.atomic_write "\x00#{dir}\x00"

      keg.relocate_build_prefix(keg, dir, newdir, files: [Pathname("../escape.bin"), outside])

      expect(outside.binread).to include dir.to_s
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

    specify "keeps suffix offsets after exact-prefix path list entries" do
      binary_file.atomic_write "\x00#{dir}:/lib\x00"

      keg.relocate_build_prefix(keg, dir, newdir)

      expect(binary_file.binread).to eq "\x00#{padded_prefix}:/lib\x00"
    end

    specify "pads every path occurrence with separators" do
      string = "#{dir}/lib:#{dir}"
      separators = "/" * (dir.to_s.length - newdir.to_s.length)

      padded = described_class.replace_prefix_preserving_length(string, dir.to_s, newdir.to_s)

      expect(padded).to eq "#{newdir}#{separators}/lib:#{newdir}#{separators}"
    end

    specify "falls back to null padding when an occurrence is not a path under the prefix" do
      string = "#{dir}-extra:#{dir}/lib"
      null_padding = "\x00" * ((dir.to_s.length - newdir.to_s.length) * 2)

      padded = described_class.replace_prefix_preserving_length(string, dir.to_s, newdir.to_s)

      expect(padded).to eq "#{newdir}-extra:#{newdir}/lib#{null_padding}"
    end

    specify "leaves prefix strings inside serialised data untouched" do
      serialised = "\x01\x1a#{dir}/lib\x02\x03"
      binary_file.atomic_write "\x00#{dir}\x00#{serialised}\x00"

      keg.relocate_build_prefix(keg, dir, newdir)

      expect(binary_file.binread).to eq "\x00#{padded_prefix}\x00#{serialised}\x00"
    end

    specify "replaces the prefix in strings of UTF-8 text" do
      binary_file.atomic_write "\x00Konfiguration „#{dir}/etc“ fehlt\x00"

      keg.relocate_build_prefix(keg, dir, newdir)

      expect(binary_file.binread).to eq "\x00Konfiguration „#{padded_prefix}/etc“ fehlt\x00".b
    end

    specify "leaves prefix strings inside long length-prefixed text untouched" do
      json = "{\"prefix\": \"#{dir}\", \"padding\": \"#{"x" * 16 * 1024}\"}"
      binary_file.atomic_write "\x00#{json}\x00"

      keg.relocate_build_prefix(keg, dir, newdir)

      expect(binary_file.binread).to eq "\x00#{json}\x00"
    end

    specify "does not rewrite recorded files without the old prefix" do
      binary_file.atomic_write "\x00unrelated\x00"
      inode = binary_file.stat.ino

      keg.relocate_build_prefix(keg, dir, newdir, files: [Pathname("file.bin")])

      expect(binary_file.stat.ino).to eq inode
    end
  end
end
