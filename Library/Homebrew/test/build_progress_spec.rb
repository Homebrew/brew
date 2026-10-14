# typed: strict
# frozen_string_literal: true

require "build_progress"

RSpec.describe BuildProgress do
  sig { returns(BuildProgress) }
  subject(:build_progress) { described_class.new(logs) }

  sig { returns(Pathname) }
  let(:logs) { mktmpdir }

  before { allow(Time).to receive(:now).and_return(Time.at(1_000_000)) }

  describe "#forward" do
    sig { params(chunks: String).returns(String) }
    def forwarded(*chunks)
      input, input_writer = IO.pipe
      output_reader, output = IO.pipe
      writer = Thread.new do
        chunks.each do |chunk|
          input_writer.write(chunk)
          sleep 0.2
        end
        input_writer.close
      end
      build_progress.forward(input, output)
      build_progress.finish(output)
      writer.join
      output.close
      output_reader.read
    end

    it "draws the spinner below the output" do
      expect(forwarded("==> make\n")).to match(/==> make\n\e\[0G\e\[K⠋ /)
    end

    it "clears the status line when finished" do
      expect(forwarded("==> make\n")).to end_with("\e[0G\e[K")
    end

    it "stops drawing once Ctrl-C is echoed" do
      output = forwarded("==> make\n", "^C", "One sec, cleaning up...\n")
      expect(output).to end_with("\e[0G\e[K^COne sec, cleaning up...\n")
    end
  end

  describe "#status" do
    it "shows only a spinner without a build log" do
      expect(build_progress.status).to eq("⠋ ")
    end

    it "shows Ninja step progress from the newest build log" do
      (logs/"01.cmake.log").write("[1708/9135] /usr/bin/clang -c foo.cpp\nfoo.cpp:1:1: warning: [-Wfoo]\n")
      expect(build_progress.status).to eq("⠋ 1708/9135 (18%)")
    end

    it "shows CMake Makefile percentage progress" do
      (logs/"01.make.log").write("[  7%] Building CXX object foo.o\n")
      expect(build_progress.status).to eq("⠋ 7%")
    end

    it "ignores compiler wrapper logs" do
      (logs/"01.cmake.log").write("[1/2] /usr/bin/clang -c foo.cpp\n")
      (logs/"01.cmake.cc.log").write("superenv executed: clang -c foo.cpp\n")
      expect(build_progress.status).to eq("⠋ 1/2 (50%)")
    end

    it "ignores logs from before the build started" do
      (logs/"01.cmake.log").write("[1/2] /usr/bin/clang -c foo.cpp\n")
      (logs/"01.cmake.log").utime(Time.at(0), Time.at(0))
      expect(build_progress.status).to eq("⠋ ")
    end
  end
end
