# typed: strict
# frozen_string_literal: true

require "formula_assertions"

RSpec.describe Homebrew::Assertions do
  sig { returns(Homebrew::Assertions) }
  subject(:formula_assertions) do
    Class.new do
      include Homebrew::Assertions
    end.new
  end

  describe "#with_test_process" do
    it "terminates and reaps the child with the requested signal" do
      formula_assertions.with_test_process("/bin/sleep", "60", signal: "INT") { nil }

      expect($CHILD_STATUS.termsig).to eq Signal.list.fetch("INT")
    end

    it "accepts a SIG-prefixed process group signal" do
      formula_assertions.with_test_process("/bin/sleep", "60", signal: "-SIGINT", pgroup: true) { nil }

      expect($CHILD_STATUS.termsig).to eq Signal.list.fetch("INT")
    end

    sig { params(leader: Symbol).returns(String) }
    def remaining_worker_output(leader)
      parent, child = UNIXSocket.pair
      leader_pid = T.let(nil, T.nilable(Integer))
      Timeout.timeout(15) do
        signal_handler = if leader == :ignore
          ":IGNORE"
        else
          ":DEFAULT"
        end
        move_group = leader == :move_group
        exit_leader = leader == :exit
        formula_assertions.with_test_process(
          RbConfig.ruby, "-e", <<~RUBY, in: child, out: child, signal: "-TERM", pgroup: true
            Signal.trap(:TERM, #{signal_handler})
            fork do
              Signal.trap(:TERM, :IGNORE)
              puts Process.pid
              $stdout.flush
              $stdin.read
            end
            if #{move_group}
              Process.setpgid(0, Process.getpgid(Process.ppid))
              puts Process.pid
              $stdout.flush
            end
            $stdin.read unless #{exit_leader}
          RUBY
        ) do |pid|
          leader_pid = pid
          child.close
          parent.readline
          parent.readline if leader == :move_group
          Process.wait(pid) if leader == :exit
        end

        parent.read
      end
    ensure
      parent&.close
      child&.close
      begin
        Timeout.timeout(5) { Process.wait(leader_pid) if leader_pid }
      rescue Errno::ECHILD
        # The helper already reaped the leader.
      end
    end

    context "when escalating to KILL" do
      before { stub_const("Homebrew::Assertions::TEST_PROCESS_GRACE_PERIOD", 0.1) }

      it "kills the worker when its leader ignores the requested signal" do
        expect(remaining_worker_output(:ignore)).to eq("")
      end

      it "kills the worker when its leader is reaped before cleanup" do
        expect(remaining_worker_output(:exit)).to eq("")
      end

      it "kills the worker when its leader exits on the requested signal" do
        expect(remaining_worker_output(:wait)).to eq("")
      end

      it "kills the worker and the leader when the leader changes process groups" do
        expect(remaining_worker_output(:move_group)).to eq("")
      end

      it "kills and reaps a child that ignores the requested signal" do
        IO.pipe do |reader, writer|
          formula_assertions.with_test_process(RbConfig.ruby, "-e", <<~RUBY, out: writer) do
            Signal.trap(:TERM, :IGNORE)
            $stdout.sync = true
            puts Process.pid
            sleep
          RUBY
            writer.close
            reader.gets
          end
        end

        expect($CHILD_STATUS.termsig).to eq Signal.list.fetch("KILL")
      end
    end

    it "preserves exceptions from the test block" do
      expect do
        formula_assertions.with_test_process("/bin/sleep", "60") { raise "test failed" }
      end.to raise_error(RuntimeError, "test failed")
    end

    it "leaves a child reaped by the test block alone" do
      expect(Process).not_to receive(:kill)

      formula_assertions.with_test_process("/bin/sh", "-c", "exit 0") { |pid| Process.wait(pid) }
    end

    it "preserves the test block's exception after it reaps the child" do
      expect do
        formula_assertions.with_test_process("/bin/sh", "-c", "exit 0") do |pid|
          Process.wait(pid)
          raise Errno::ECHILD, "test failed"
        end
      end.to raise_error(Errno::ECHILD, /test failed/)
    end

    it "preserves errors when spawning the child fails" do
      expect do
        formula_assertions.with_test_process((mktmpdir/"missing-executable").to_s) { nil }
      end.to raise_error(Errno::ENOENT)
    end

    it "rejects an implicit shell command" do
      expect do
        formula_assertions.with_test_process("/bin/echo ready | /bin/cat", out: File::NULL) { nil }
      end.to raise_error(Errno::ENOENT)
    end

    it "runs a single executable path containing shell metacharacters literally" do
      executable = mktmpdir/"test & command"
      executable.write("#!/bin/sh\nexit 27\n")
      executable.chmod(0755)

      formula_assertions.with_test_process(executable.to_s) { |pid| Process.wait(pid) }

      expect($CHILD_STATUS.exitstatus).to eq(27)
    end

    it "rejects an invalid signal before spawning the child" do
      allow(Process).to receive(:spawn).and_raise("spawned before signal validation")

      expect do
        formula_assertions.with_test_process("/bin/sleep", "60", signal: "TERMM") { nil }
      end.to raise_error(ArgumentError, /TERMM/)
    end

    it "forwards spawn options" do
      IO.pipe do |reader, writer|
        formula_assertions.with_test_process("/bin/echo", "ready", [:out, :err] => writer) do
          expect(reader.gets).to eq("ready\n")
        end
      end
    end
  end

  it "preserves the shell exit status for a non-executable Pathname" do
    executable = mktmpdir/"not-executable"
    executable.write("")

    expect(formula_assertions.shell_output(executable, 126)).to eq("")
  end

  it "preserves shell syntax for String commands" do
    expect(formula_assertions.shell_output("printf shell | /bin/cat")).to eq("shell")
  end

  it "passes Pathname metacharacters literally" do
    executable = mktmpdir/"directory;$(false)"/"executable"
    executable.dirname.mkpath
    executable.write("#!/bin/sh\nprintf literal\n")
    executable.chmod(0755)

    expect(formula_assertions.shell_output(executable)).to eq("literal")
  end

  it "executes a relative Pathname literally rather than through PATH" do
    directory = mktmpdir
    (directory/"tool").write("#!/bin/sh\nprintf local\n")
    (directory/"tool").chmod(0755)
    shadow = directory/"shadow"
    shadow.mkpath
    (shadow/"tool").write("#!/bin/sh\nprintf shadowed\n")
    (shadow/"tool").chmod(0755)
    ENV["PATH"] = "#{shadow}:/usr/bin:/bin"

    expect(directory.cd { formula_assertions.shell_output(Pathname("tool")) }).to eq("local")
  end
end
