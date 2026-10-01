# typed: true
# frozen_string_literal: true

require "utils/popen"
require "timeout"
require "socket"

RSpec.describe Utils do
  describe "::popen" do
    shared_examples "interruptible popen" do
      it "kills an interrupted command and its descendants" do
        error = Timeout::ExitException.new("test expired")

        UNIXServer.open((mktmpdir/"socket").to_s) do |server|
          connection = T.let(nil, T.nilable(UNIXSocket))
          expect do
            described_class.popen([RbConfig.ruby, "-rsocket", "-e", <<~RUBY, server.path], "r+") do
              fork do
                UNIXSocket.open(ARGV.fetch(0)) do |socket|
                  $stdin.read
                  socket.write("survived")
                end
              end
              Process.wait
            RUBY
              connection = server.accept
              raise error
            end
          end.to raise_error(error)

          expect([$CHILD_STATUS.termsig, connection&.read]).to eq([Signal.list.fetch("KILL"), ""])
        ensure
          connection&.close
        end
      end

      it "preserves an exception after closing the pipe" do
        expect do
          described_class.popen_read(RbConfig.ruby, "-e", "exit") do |pipe|
            pipe.close
            raise Interrupt
          end
        end.to raise_error(Interrupt)
      end

      it "waits normally inside a rescue" do
        begin
          raise "previous failure"
        rescue RuntimeError
          described_class.popen([RbConfig.ruby, "-e", '$stdout.sync = true; puts "ready"; $stdin.read'], "r+", &:gets)
        end

        expect($CHILD_STATUS).to be_a_success
      end
    end

    context "when forking" do
      before { ENV["HOMEBREW_SPAWN_SYSTEM"] = "0" }

      include_examples "interruptible popen"
    end

    context "when spawning" do
      before { ENV["HOMEBREW_SPAWN_SYSTEM"] = "1" }

      include_examples "interruptible popen"
    end
  end

  describe "::popen_read" do
    it "reads the standard output of a given command" do
      expect(described_class.popen_read("sh", "-c", "echo success").chomp).to eq("success")
      expect($CHILD_STATUS).to be_a_success
    end

    it "can be given a block to manually read from the pipe" do
      expect(
        described_class.popen_read("sh", "-c", "echo success") do |pipe|
          pipe.read.chomp
        end,
      ).to eq("success")
      expect($CHILD_STATUS).to be_a_success
    end

    it "fails when the command does not exist" do
      expect(described_class.popen_read("./nonexistent", err: :out))
        .to eq("brew: command not found: ./nonexistent\n")
      expect($CHILD_STATUS).to be_a_failure
    end

    it "captures merged stderr when spawning instead of forking" do
      ENV["HOMEBREW_SPAWN_SYSTEM"] = "1"

      expect(described_class.popen_read("/bin/sh", "-c", "printf error >&2", err: :out)).to eq("error")
    end
  end

  describe "::popen_read_text" do
    it "returns output in the default external encoding" do
      output = described_class.popen_read_text("/usr/bin/printf", "café")

      expect([output, output.encoding, $CHILD_STATUS.success?]).to eq(["café", Encoding.default_external, true])
    end
  end

  describe "::popen_write" do
    let(:foo) { mktmpdir/"foo" }

    before { foo.write "Foo\n" }

    it "supports writing to a command's standard input" do
      described_class.popen_write("grep", "-q", "success") do |pipe|
        pipe.write "success\n"
      end
      expect($CHILD_STATUS).to be_a_success
    end

    it "returns the command's standard output before writing" do
      child_stdout = described_class.popen_write("cat", foo, "-") do |pipe|
        pipe.write "Bar\n"
      end
      expect($CHILD_STATUS).to be_a_success
      expect(child_stdout).to eq <<~EOS
        Foo
        Bar
      EOS
    end

    it "returns the command's standard output after writing" do
      child_stdout = described_class.popen_write("cat", "-", foo) do |pipe|
        pipe.write "Bar\n"
      end
      expect($CHILD_STATUS).to be_a_success
      expect(child_stdout).to eq <<~EOS
        Bar
        Foo
      EOS
    end

    it "supports interleaved writing between two reads" do
      child_stdout = described_class.popen_write("cat", foo, "-", foo) do |pipe|
        pipe.write "Bar\n"
      end
      expect($CHILD_STATUS).to be_a_success
      expect(child_stdout).to eq <<~EOS
        Foo
        Bar
        Foo
      EOS
    end
  end

  describe "::safe_popen_read" do
    it "does not raise an error if the command succeeds" do
      expect(described_class.safe_popen_read("sh", "-c", "true")).to eq("")
      expect($CHILD_STATUS).to be_a_success
    end

    it "raises an error if the command fails" do
      expect { described_class.safe_popen_read("sh", "-c", "false") }.to raise_error(ErrorDuringExecution)
      expect($CHILD_STATUS).to be_a_failure
    end
  end

  describe "::safe_popen_write" do
    it "does not raise an error if the command succeeds" do
      expect do
        described_class.safe_popen_write("grep", "success") { |pipe| pipe.write "success\n" }
      end.not_to raise_error
      expect($CHILD_STATUS).to be_a_success
    end

    it "raises an error if the command fails" do
      expect do
        described_class.safe_popen_write("grep", "success") { |pipe| pipe.write "failure\n" }
      end.to raise_error(ErrorDuringExecution)
      expect($CHILD_STATUS).to be_a_failure
    end
  end
end
