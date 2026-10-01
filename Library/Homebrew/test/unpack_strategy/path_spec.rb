# typed: strict
# frozen_string_literal: true

require "unpack_strategy"

RSpec.describe UnpackStrategy::Path do
  sig { returns(UnpackStrategy::Path) }
  subject(:path) { described_class.new(TEST_FIXTURE_DIR/"cask/container.zip") }

  it "caches the magic number" do
    expect(path).to receive(:binread).with(262).once.and_return("PK\x03\x04")

    2.times { path.magic_number }
  end

  it "returns an empty magic number for directories" do
    expect(described_class.new(mktmpdir).magic_number).to eq("")
  end

  it "caches the file type" do
    expect(path).to receive(:system_command)
      .with("file", args: ["-b", path], print_stderr: false)
      .once.and_return(instance_double(SystemCommand::Result, stdout: "Zip archive\n"))

    2.times { path.file_type }
  end

  it "caches ZIP entries" do
    expect(path).to receive(:system_command)
      .with("zipinfo", args: ["-1", path], print_stderr: false)
      .once.and_return(instance_double(SystemCommand::Result, stdout: "container/\n"))

    2.times { path.zipinfo }
  end

  it "replaces invalid UTF-8 in ZIP entries" do
    allow(path).to receive(:system_command)
      .and_return(instance_double(SystemCommand::Result, stdout: "invalid\xFF\n"))

    expect(path.zipinfo).to eq(["invalid\uFFFD"])
  end
end
