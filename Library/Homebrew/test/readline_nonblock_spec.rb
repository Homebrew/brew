# typed: strict
# frozen_string_literal: true

require "readline_nonblock"

RSpec.describe ReadlineNonblock do
  describe "#read", timeout: 10 do
    it "returns only full lines", :aggregate_failures do
      IO.pipe do |read_io, write_io|
        reader = described_class.new(read_io)
        expect { reader.read }.to raise_error(IO::WaitReadable)
        write_io.write "Test"
        expect { reader.read }.to raise_error(IO::WaitReadable)
        write_io.write "1\n2"
        expect(reader.read).to eq("Test1\n")
        write_io.close
        expect(reader.read).to eq("2")
        expect { reader.read }.to raise_error(EOFError)
      end
    end

    it "returns same lines from file as File.readlines" do
      mktmpdir do |tmpdir|
        (tmpdir/"test.txt").write <<~EOS.chomp
          First line
          Second line

          Fourth line
          Fifth line
        EOS

        lines = []
        (tmpdir/"test.txt").open do |file|
          reader = described_class.new(file)
          loop do
            lines << reader.read
          rescue IO::WaitReadable
            file.wait_readable
          rescue EOFError
            break
          end
        end
        expect(lines).to eq(File.readlines(tmpdir/"test.txt"))
        expect(lines).to eq ["First line\n", "Second line\n", "\n", "Fourth line\n", "Fifth line"]
      end
    end

    it "handles long lines" do
      IO.pipe do |read_io, write_io|
        line_length = 10000
        write_io.write("a" * line_length)
        write_io.close
        reader = described_class.new(read_io)
        expect(reader.read.length).to eq line_length
        expect { reader.read }.to raise_error(EOFError)
      end
    end
  end
end
