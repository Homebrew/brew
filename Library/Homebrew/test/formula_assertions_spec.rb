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

    it "kills the process group when it ignores the requested signal" do
      parent, child = UNIXSocket.pair
      formula_assertions.with_test_process(
        RbConfig.ruby, "-e", <<~RUBY, in: child, out: child, signal: "-TERM", pgroup: true
          Signal.trap(:TERM, :IGNORE)
          fork do
            puts Process.pid
            $stdout.flush
            $stdin.read
          end
          $stdin.read
        RUBY
      ) do
        child.close
        parent.readline
      end

      expect(Timeout.timeout(5) { parent.read }).to eq("")
    ensure
      parent&.close
      child&.close
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
