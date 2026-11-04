# typed: strict
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require "dev-cmd/unpack"

RSpec.describe Homebrew::DevCmd::Unpack do
  it_behaves_like "parseable arguments"

  context "with a cached Cask archive", :cask do
    test_each [".zip", ".tar.gz"] do |extension|
      it "preserves the destination when a cached #{extension} checksum does not match" do
        cached_download = Cask::Download.new(Cask::CaskLoader.load("local-caffeine")).cached_download
        cached_download.dirname.mkpath
        FileUtils.cp TEST_FIXTURE_DIR/"cask/container.tar.gz", cached_download.sub_ext(extension)
        unpack_dir = mktmpdir
        stage_dir = unpack_dir/"local-caffeine-1.2.3"
        stage_dir.mkpath
        existing_file = stage_dir/"existing.txt"
        existing_file.write("existing contents")

        expect { described_class.new(["--cask", "local-caffeine", "--force", "--destdir=#{unpack_dir}"]).run }
          .to raise_error(ChecksumMismatchError) do
            expect(existing_file.read).to eq("existing contents")
          end
      end
    end
  end

  it "unpacks a given Formula and Cask archive", :cask, :integration_test do
    setup_test_formula "testball"

    mktmpdir do |path|
      expect { brew "unpack", "testball", "--destdir=#{path}" }
        .to be_a_success

      expect(path/"testball-0.1").to be_a_directory
    end

    mktmpdir do |path|
      expect { brew "unpack", "--cask", "local-caffeine", "--destdir=#{path}" }
        .to be_a_success

      expect(path/"local-caffeine-1.2.3").to be_a_directory
    end
  end
end
