# typed: strict
# frozen_string_literal: true

require "system_command"

require "utils/fork"
require "timeout"

RSpec.describe Utils do
  describe "::child_error_hash" do
    it "preserves build error details" do
      error = BuildError.new(nil, "make", ["install"], { "PATH" => "/bin" })

      expect(described_class.child_error_hash(error)).to include(
        "cmd" => "make", "args" => ["install"], "env" => { "PATH" => "/bin" },
      )
    end

    it "serialises the class, message and backtrace that the parent reads back" do
      error = RuntimeError.new("child failed")
      error.set_backtrace ["/some/file.rb:1:in 'block'"]

      expect(described_class.child_error_hash(error)).to eq(
        "json_class" => "RuntimeError",
        "m"          => "child failed",
        "b"          => ["/some/file.rb:1:in 'block'"],
      )
    end
  end

  describe "#safe_fork" do
    it "preserves a parent failure while the child error pipe is open" do
      IO.pipe do |ready_read, ready_write|
        expect do
          described_class.safe_fork(yield_parent: true) do |error_pipe|
            if error_pipe
              ready_read.close
              ready_write.puts "ready"
              ready_write.close
            else
              ready_write.close
              ready_read.gets
              raise "parent failed"
            end
          end
        end.to raise_error(RuntimeError, "parent failed")
      end
    end

    it "responds to messages from the forked child" do
      messages = []
      handler = proc do |message|
        messages << message.chomp
        "acknowledged"
      end

      described_class.safe_fork(child_message_handler: handler) do
        channel = described_class.forked_child_channel
        channel.puts "privileged step"
        channel.flush
        raise "parent did not acknowledge child message" if channel.gets != "acknowledged\n"

        channel.close
      end

      expect(messages).to eq(["privileged step"])
    end

    it "interrupts a child waiting for a parent response without deadlocking" do
      expect do
        Timeout.timeout(2) do
          handler = proc do |_message|
            raise Interrupt
          end
          described_class.safe_fork(child_message_handler: handler) do
            channel = described_class.forked_child_channel
            channel.puts "privileged step"
            channel.flush
            channel.gets
            channel.close
          end
        end
      end.to raise_error(Interrupt)
    end

    it "reaps the child when a parent message handler raises" do
      child_pid = T.let(nil, T.nilable(Integer))
      handler = proc do |message|
        child_pid = message.to_i
        raise "parent message handler failed"
      end

      expect do
        described_class.safe_fork(child_message_handler: handler) do
          channel = described_class.forked_child_channel
          channel.puts Process.pid.to_s
          channel.flush
          channel.close
        end
      end.to raise_error(RuntimeError, "parent message handler failed")

      pid = child_pid
      raise "child did not send its process ID" unless pid

      expect { Process.waitpid(pid) }.to raise_error(Errno::ECHILD)
    end

    it "raises a RuntimeError on an error that isn't ErrorDuringExecution" do
      expect do
        described_class.safe_fork do
          raise "this is an exception in the child"
        end
      end.to raise_error(RuntimeError)
    end

    it "raises an ErrorDuringExecution on one in the child" do
      expect do
        described_class.safe_fork do
          SystemCommand.safe_system "/usr/bin/false"
        end
      end.to raise_error(ErrorDuringExecution)
    end
  end
end
