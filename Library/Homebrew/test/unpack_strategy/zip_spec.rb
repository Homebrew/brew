# typed: true
# frozen_string_literal: true

require "zlib"

require_relative "shared_examples"

RSpec.describe UnpackStrategy::Zip do
  subject(:path) { TEST_FIXTURE_DIR/"cask/MyFancyApp.zip" }

  include_examples "UnpackStrategy::detect"

  context "when unzip is available", :needs_unzip do
    include_examples "#extract", children: ["MyFancyApp"]
  end

  context "when ZIP archive is corrupted" do
    subject(:path) do
      (mktmpdir/"test.zip").tap do |path|
        FileUtils.touch path
      end
    end

    include_examples "UnpackStrategy::detect"
  end

  context "when the archive contains a volume label", :needs_macos, :needs_unzip do
    let(:root) { mktmpdir }
    let(:unpack_dir) { (root/"unpack").tap(&:mkpath) }
    let(:zip_path) { root/"volume-label.zip" }

    # A member reads as a volume label when its host is FAT (0) and its MS-DOS attributes
    # set the label bit (0x08), and as a symlink when its host is Unix (3) and its mode
    # says so. `unzip` skips the former and names it on stderr, which is what gets scraped.
    def write_zip(path, members)
      local = +""
      central = +""
      members.each do |name, data, host, external_attrs|
        crc = Zlib.crc32(data)
        offset = local.bytesize
        local << ["PK\x03\x04", 10, 0, 0, 0, 0, crc, data.bytesize, data.bytesize,
                  name.bytesize, 0].pack("a4v5V3v2") << name << data
        central << ["PK\x01\x02", (host << 8) | 20, 10, 0, 0, 0, 0, crc, data.bytesize, data.bytesize,
                    name.bytesize, 0, 0, 0, 0, external_attrs, offset].pack("a4v6V3v5V2") << name
      end
      path.binwrite(local + central +
                    ["PK\x05\x06", 0, 0, members.size, members.size,
                     central.bytesize, local.bytesize, 0].pack("a4v4V2v"))
    end

    it "does not move the label member through a planted symlink of the same name" do
      outside = (root/"outside").tap(&:mkpath)
      name = "A" * 24
      write_zip(zip_path, [[name, "label\n", 0, 0x08], [name, outside.to_s, 3, 0120777 << 16]])

      described_class.new(zip_path).extract(to: unpack_dir)

      expect(outside.children).to be_empty
    end

    # `unpack_dir` can be on another filesystem, as `brew unpack --destdir` allows, and
    # `FileUtils.mv` then copies rather than renames, opening the destination path.
    it "does not write through a planted symlink when moving across filesystems" do
      victim = root/"victim"
      victim.write "original\n"
      name = "A" * 24
      write_zip(zip_path, [[name, "label\n", 0, 0x08], [name, victim.to_s, 3, 0120777 << 16]])
      allow(File).to receive(:rename).and_raise(Errno::EXDEV)

      described_class.new(zip_path).extract(to: unpack_dir)

      expect(victim.read).to eq("original\n")
    end

    it "confines a label member whose name traverses upwards" do
      name = "../../../victimfileAAAAAAAAAAAAAA"
      write_zip(zip_path, [[name, "label\n", 0, 0x08]])

      described_class.new(zip_path).extract(to: unpack_dir)

      expect(unpack_dir.children.map { |child| child.basename.to_s }).to contain_exactly(File.basename(name))
    end

    it "still extracts a label member that no symlink shadows" do
      name = "SomeDiskImageVolumeLabel.dmg"
      write_zip(zip_path, [["readme.txt", "hi\n", 3, 0100644 << 16], [name, "disk image\n", 0, 0x08]])

      described_class.new(zip_path).extract(to: unpack_dir)

      expect(unpack_dir.children.map { |child| child.basename.to_s }).to contain_exactly("readme.txt", name)
    end
  end
end
