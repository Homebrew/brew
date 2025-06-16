# frozen_string_literal: true

RSpec.describe UnpackStrategy do
  describe "#extract_nestedly" do
    subject(:strategy) { described_class.detect(path) }

    let(:unpack_dir) { mktmpdir }

    context "when extracting a GZIP nested in a BZIP2" do
      let(:file_name) { "file" }
      let(:path) do
        dir = mktmpdir

        (dir/"file").write "This file was inside a GZIP inside a BZIP2."
        system "gzip", dir.children.first
        system "bzip2", dir.children.first

        dir.children.first
      end

      it "can extract nested archives" do
        strategy.extract_nestedly(to: unpack_dir)

        expect(File.read(unpack_dir/file_name)).to eq("This file was inside a GZIP inside a BZIP2.")
      end
    end

    context "when extracting a directory with nested directories" do
      let(:directories) { "A/B/C" }
      let(:executable) { "#{directories}/executable" }
      let(:writable) { true }
      let(:path) do
        (mktmpdir/"file.tar").tap do |path|
          Dir.mktmpdir do |dir|
            dir = Pathname(dir)
            (dir/directories).mkpath
            FileUtils.touch dir/executable
            FileUtils.chmod 0555, dir/executable

            FileUtils.chmod "-w", dir/directories unless writable
            begin
              system "tar", "--create", "--file", path, "--directory", dir, "A/"
            ensure
              FileUtils.chmod "+w", dir/directories unless writable
            end
          end
        end
      end

      it "does not recurse into nested directories" do
        strategy.extract_nestedly(to: unpack_dir)
        expect(Pathname.glob(unpack_dir/"**/*")).to include unpack_dir/directories
      end

      context "which are not writable" do
        let(:writable) { false }

        it "makes them writable but not world-writable" do
          strategy.extract_nestedly(to: unpack_dir)

          expect(unpack_dir/directories).to be_writable
          expect(unpack_dir/directories).not_to be_world_writable
        end

        it "does not make other files writable" do
          strategy.extract_nestedly(to: unpack_dir)

          # We don't check `writable?` here as that's always true as root.
          expect((unpack_dir/executable).stat.mode & 0222).to be_zero
        end
      end
    end

    context "when extracting a nested archive" do
      let(:basename) { "file.xyz" }
      let(:path) do
        (mktmpdir/basename).tap do |path|
          mktmpdir do |dir|
            FileUtils.touch dir/"file.txt"
            system "tar", "--create", "--file", path, "--directory", dir, "file.txt"
          end
        end
      end

      it "does not pass down the basename of the archive" do
        strategy.extract_nestedly(to: unpack_dir, basename:)
        expect(unpack_dir/"file.txt").to be_a_file
      end
    end
  end
end
