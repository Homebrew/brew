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
      .once
      .and_return(instance_double(SystemCommand::Result, stdout: "Zip archive\n"))

    2.times { path.file_type }
  end

  it "caches ZIP entries" do
    expect(path).to receive(:system_command)
      .with("zipinfo", args: ["-1", anything], print_stderr: false)
      .once
      .and_return(instance_double(SystemCommand::Result, stdout: "container/\n"))

    2.times { path.zipinfo }
  end

  it "replaces invalid UTF-8 in ZIP entries" do
    allow(path).to receive(:system_command)
      .and_return(instance_double(SystemCommand::Result, stdout: "invalid\xFF\n"))

    expect(path.zipinfo).to eq(["invalid\uFFFD"])
  end

  context "when ZIP tools are available", :needs_unzip do
    test_each ["x[!?]incomplete", "x?incomplete", "x*incomplete"] do |name|
      it "lists only the archive named #{name}" do
        directory = mktmpdir
        FileUtils.cp TEST_FIXTURE_DIR/"cask/caffeine.zip", directory/"x.incomplete"
        FileUtils.cp TEST_FIXTURE_DIR/"cask/MyFancyApp.zip", directory/name

        expect(described_class.new(directory/name).zipinfo)
          .to eq(described_class.new(TEST_FIXTURE_DIR/"cask/MyFancyApp.zip").zipinfo)
      end
    end

    test_each ["zip", "ZIP"] do |extension|
      it "does not list a neighbouring .#{extension} archive" do
        archive = mktmpdir/"invalid.zip"
        archive.write "not a ZIP archive"
        FileUtils.cp TEST_FIXTURE_DIR/"cask/MyFancyApp.zip", "#{archive}.#{extension}"

        expect(described_class.new(archive).zipinfo).to be_empty
      end
    end
  end

  describe "#with_literal_name" do
    sig { returns(UnpackStrategy::Path) }
    subject(:path) { described_class.new(TEST_FIXTURE_DIR/"cask/MyFancyApp.zip") }

    it "uses a fixed name in an otherwise empty temporary directory" do
      expect(path.with_literal_name do |archive|
        [archive.basename.to_s, archive.realpath, archive.dirname.children.size]
      end)
        .to eq(["archive", path.realpath, 1])
    end

    it "cleans up in the configured temporary directory" do
      temporary_directory = mktmpdir
      parent = path.with_literal_name(temporary_directory:) { |archive| archive.dirname.parent }

      expect([parent, temporary_directory.children]).to eq([temporary_directory, []])
    end

    it "cleans up when the block raises" do
      temporary_directory = mktmpdir

      result = begin
        path.with_literal_name(temporary_directory:) { raise "test failure" }
      rescue RuntimeError => e
        [e.message, temporary_directory.children]
      end

      expect(result).to eq(["test failure", []])
    end

    it "keeps the source path and command details without chaining the error" do
      error = ErrorDuringExecution.new(["unzip", "-broken"], status: 9,
                                                             output: [[:stderr, "archive unreadable\n"]])

      result = begin
        path.with_literal_name { raise error }
      rescue ErrorDuringExecution => e
        e
      end

      expect(result).to have_attributes(
        class:      error.class,
        message:    a_string_including(path.to_s, error.message),
        cmd:        error.cmd,
        status:     error.status,
        exitstatus: 9,
        stderr:     error.stderr,
        output:     error.output,
        backtrace:  error.backtrace,
        cause:      nil,
      )
    end
  end
end
