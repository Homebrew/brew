# frozen_string_literal: true

require "cask/artifact/relocated"

RSpec.describe Cask::Artifact::Relocated, :cask do
  let(:cask) do
    Cask::Cask.new("test-cask") do
      url "file://#{TEST_FIXTURE_DIR}/cask/caffeine.zip"
      homepage "https://brew.sh/"
      version "1.0"
      sha256 "67cdb8a02803ef37fdbf7e0be205863172e41a561ca446cd84f0d7ab35a99d94"
    end
  end

  let(:command) { NeverSudoSystemCommand }
  let(:artifact) { described_class.new(cask, "test_file.txt") }

  describe "#add_altname_metadata" do
    let(:file) { Pathname("/tmp/test_file.txt") }
    let(:altname) { Pathname("alternate_name.txt") }

    before do
      allow(file).to receive_messages(basename: Pathname("test_file.txt"), writable?: true, realpath: file)
    end

    context "when running on Linux", :needs_linux do
      it "is a no-op and does not call xattr commands" do
        expect(command).not_to receive(:run)
        expect(command).not_to receive(:run!)

        artifact.send(:add_altname_metadata, file, altname, command: command)
      end
    end

    context "when running on macOS", :needs_macos do
      before do
        stdout_double = instance_double(SystemCommand::Result, stdout: "")
        allow(command).to receive(:run).and_return(stdout_double)
        allow(command).to receive(:run!)
      end

      it "calls xattr commands to set metadata" do
        expect(command).to receive(:run).with("/usr/bin/xattr",
                                              args:         ["-p", "com.apple.metadata:kMDItemAlternateNames", file],
                                              print_stderr: false)
        expect(command).to receive(:run!).twice

        artifact.send(:add_altname_metadata, file, altname, command: command)
      end
    end
  end
end
