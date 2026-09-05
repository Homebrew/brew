# typed: false
# frozen_string_literal: true

require "pty"
require "system_command"

RSpec.describe SystemCommand do
  describe ".safe_system" do
    include Context

    it "raises when the command fails" do
      expect { described_class.safe_system("false") }.to raise_error(ErrorDuringExecution)
    end

    it "exits with 1 when the command cannot be run" do
      expect { described_class.safe_system("brew-missing-command") }
        .to raise_error(ErrorDuringExecution, /exited with 1\./)
    end

    it "runs the command attached to the terminal" do
      PTY.open do |_control, terminal|
        $stdin.reopen(terminal)

        expect { described_class.safe_system("sh", "-c", "test -t 0") }.not_to raise_error
      end
    end

    it "sets the given environment" do
      expect do
        described_class.safe_system("sh", "-c", 'test "$BREW_TEST_VARIABLE" = value',
                                    env: { "BREW_TEST_VARIABLE" => "value" })
      end.not_to raise_error
    end

    it "redirects standard output to standard error" do
      expect { described_class.safe_system("echo", "redirected", out: :err) }
        .to output("redirected\n").to_stderr_from_any_process
    end

    it "prints the command when verbose" do
      with_context(verbose: true) do
        expect { described_class.safe_system("true", "--version") }.to output("true --version\n").to_stdout
      end
    end
  end

  describe ".quiet_system" do
    it "returns the command status" do
      expect(described_class.quiet_system("true")).to be true
      expect(described_class.quiet_system("false")).to be false
    end

    it "sets the child status" do
      described_class.quiet_system("sh", "-c", "exit 3")

      expect($CHILD_STATUS.exitstatus).to eq(3)
    end

    it "discards the command output" do
      reader, writer = IO.pipe
      Utils::Output.redirect_stdout(writer) { described_class.quiet_system("echo", "discarded") }
      writer.close

      expect(reader.read).to be_empty
    end
  end

  describe SystemCommand::Helpers do
    subject(:helpers) { Class.new { include SystemCommand::Helpers }.new }

    it "provides positional system helpers" do
      expect(SystemCommand).to receive(:safe_system).with("true")
      expect(SystemCommand).to receive(:quiet_system).with("true").and_return(true)

      helpers.safe_system("true")
      expect(helpers.quiet_system("true")).to be true
    end
  end

  describe "#initialize" do
    subject(:command) do
      described_class.new(
        "env",
        args:         env_args,
        env:,
        must_succeed: true,
        sudo:,
        sudo_as_root:,
      )
    end

    let(:env_args) { ["bash", "-c", 'printf "%s" "${A?}" "${B?}" "${C?}"'] }
    let(:env) { { "A" => "1", "B" => "2", "C" => "3" } }
    let(:sudo) { false }
    let(:sudo_as_root) { false }

    context "when given some environment variables" do
      it("run!.stdout") { expect(command.run!.stdout).to eq("123") }

      describe "the resulting command line" do
        it "includes the given variables explicitly" do
          expect(command)
            .to receive(:exec3)
            .with(
              an_instance_of(Hash), "/usr/bin/env", "A=1", "B=2", "C=3",
              "env", *env_args,
              pgroup: true
            )
            .and_call_original

          command.run!
        end
      end
    end

    context "when given an environment variable which is set to nil" do
      let(:env) { { "A" => "1", "B" => "2", "C" => nil } }

      it "unsets them" do
        expect do
          command.run!
        end.to raise_error(/C: parameter (?:null or )?not set/)
      end
    end

    context "when given some environment variables and sudo: true, sudo_as_root: false" do
      let(:sudo) { true }
      let(:sudo_as_root) { false }

      describe "the resulting command line" do
        it "includes the given variables explicitly" do
          expect(command)
            .to receive(:exec3)
            .with(
              an_instance_of(Hash), "/usr/bin/sudo", "-E",
              "A=1", "B=2", "C=3", "--", "env", *env_args, pgroup: nil
            )
            .and_wrap_original do |original_exec3, *_, &block|
              original_exec3.call({}, "true", &block)
            end

          command.run!
        end
      end
    end

    context "when given some environment variables and sudo: true, sudo_as_root: true" do
      let(:sudo) { true }
      let(:sudo_as_root) { true }

      describe "the resulting command line" do
        it "includes the given variables explicitly" do
          expect(command)
            .to receive(:exec3)
            .with(
              an_instance_of(Hash), "/usr/bin/sudo", "-u", "root",
              "-E", "A=1", "B=2", "C=3", "--", "env", *env_args, pgroup: nil
            )
            .and_wrap_original do |original_exec3, *_, &block|
              original_exec3.call({}, "true", &block)
            end

          command.run!
        end
      end
    end
  end

  context "when the exit code is 0" do
    describe "its result" do
      subject(:result) { described_class.run("true") }

      it { is_expected.to be_a_success }
      it(:exit_status) { expect(result.exit_status).to eq(0) }
    end
  end

  context "when the exit code is 1" do
    let(:command) { "false" }

    context "with a command that must succeed" do
      it "throws an error" do
        expect do
          described_class.run!(command)
        end.to raise_error(ErrorDuringExecution)
      end
    end

    context "with a command that does not have to succeed" do
      describe "its result" do
        subject(:result) { described_class.run(command) }

        it { is_expected.not_to be_a_success }
        it(:exit_status) { expect(result.exit_status).to eq(1) }
      end
    end
  end

  context "when given a pathname" do
    let(:command) { "/bin/ls" }
    let(:path)    { Pathname(Dir.mktmpdir) }

    before do
      FileUtils.touch(path.join("somefile"))
    end

    describe "its result" do
      subject(:result) { described_class.run(command, args: [path]) }

      it { is_expected.to be_a_success }
      it(:stdout) { expect(result.stdout).to eq("somefile\n") }
    end
  end

  context "with both STDOUT and STDERR output from upstream" do
    let(:command) { "/bin/bash" }
    let(:options) do
      { args: [
        "-c",
        "for i in $(seq 1 2 5); do echo $i; echo $(($i + 1)) >&2; done",
      ] }
    end

    shared_examples "it returns '1 2 3 4 5 6'" do
      describe "its result" do
        subject(:result) { described_class.run(command, **options) }

        it { is_expected.to be_a_success }
        it(:stdout) { expect(result.stdout).to eq([1, 3, 5, nil].join("\n")) }
        it(:stderr) { expect(result.stderr).to eq([2, 4, 6, nil].join("\n")) }
      end
    end

    context "with default options" do
      it "echoes only STDERR" do
        expected = [2, 4, 6].map { |i| "#{i}\n" }.join
        expect do
          described_class.run(command, **options)
        end.to output(expected).to_stderr
      end

      include_examples("it returns '1 2 3 4 5 6'")
    end

    context "with `print_stdout: true`" do
      before do
        options.merge!(print_stdout: true)
      end

      it "echoes both STDOUT and STDERR" do
        expect { described_class.run(command, **options) }
          .to output("1\n3\n5\n").to_stdout
          .and output("2\n4\n6\n").to_stderr
      end

      include_examples("it returns '1 2 3 4 5 6'")
    end

    context "with `print_stdout: :debug`" do
      before do
        options.merge!(print_stdout: :debug)
      end

      it "echoes only STDERR output" do
        expect { described_class.run(command, **options) }
          .to output("2\n4\n6\n").to_stderr
          .and not_to_output.to_stdout
      end

      context "when `verbose?` and `debug?` are true" do
        include Context

        let(:options) do
          { args: [
            "-c",
            "for i in $(seq 1 2 5); do echo $i; sleep 0.1; echo $(($i + 1)) >&2; sleep 0.1; done",
          ] }
        end

        it "echoes the command and all output to STDERR" do
          with_context(verbose: true, debug: true) do
            expect { described_class.run(command, **options) }
              .to output(/\A.*#{Regexp.escape(command)}.*\n1\n2\n3\n4\n5\n6\n\Z/).to_stderr
              .and not_to_output.to_stdout
          end
        end
      end

      include_examples("it returns '1 2 3 4 5 6'")
    end

    context "with `print_stderr: false`" do
      before do
        options.merge!(print_stderr: false)
      end

      it "echoes nothing" do
        expect do
          described_class.run(command, **options)
        end.not_to output.to_stdout
      end

      include_examples("it returns '1 2 3 4 5 6'")
    end

    context "with `print_stdout: true` and `print_stderr: false`" do
      before do
        options.merge!(print_stdout: true, print_stderr: false)
      end

      it "echoes only STDOUT" do
        expected = [1, 3, 5].map { |i| "#{i}\n" }.join
        expect do
          described_class.run(command, **options)
        end.to output(expected).to_stdout
      end

      include_examples("it returns '1 2 3 4 5 6'")
    end
  end

  context "with a very long STDERR output" do
    let(:command) { "/bin/bash" }
    let(:options) do
      { args: [
        "-c",
        "for i in $(seq 1 2 100000); do echo $i; echo $(($i + 1)) >&2; done",
      ] }
    end

    it "returns without deadlocking", timeout: 30 do
      expect(described_class.run(command, **options)).to be_a_success
    end
  end

  context "when the timeout expires" do
    it "kills the whole process group, including descendants ignoring TERM" do
      pid_file = mktmpdir/"pid"
      script = "(trap '' TERM; exec sleep 30) & echo $! > #{pid_file}; wait"
      expect { described_class.run("/bin/sh", args: ["-c", script], timeout: 0.5) }.to raise_error(Timeout::Error)

      grandchild_pid = pid_file.read.to_i
      # The orphaned grandchild is reaped by `init`/`launchd` asynchronously.
      expect do
        10.times do
          Process.kill(0, grandchild_pid)
          sleep(0.1)
        end
      end.to raise_error(Errno::ESRCH)
    end
  end

  context "when given an invalid variable name" do
    it "raises an ArgumentError" do
      expect { described_class.run("true", env: { "1ABC" => true }) }
        .to raise_error(ArgumentError, /variable name/)
    end
  end

  it "looks for executables in a custom PATH" do
    mktmpdir do |path|
      (path/"tool").write <<~SH
        #!/bin/sh
        echo Hello, world!
      SH

      FileUtils.chmod "+x", path/"tool"

      expect(described_class.run("tool", env: { "PATH" => path.to_s }).stdout).to include "Hello, world!"
    end
  end

  describe "#run" do
    it "does not raise a `SystemCallError` when the executable does not exist" do
      expect do
        described_class.run("non_existent_executable")
      end.not_to raise_error
    end

    it "uses `Process.spawn` rather than `fork` when no privilege change is required" do
      command = described_class.new("true")
      expect(command).not_to receive(:fork)
      expect(Process).to receive(:spawn).and_call_original
      command.run!
    end

    it 'does not format `stderr` when it starts with \r' do
      expect do
        Class.new.extend(SystemCommand::Mixin).system_command \
          "bash",
          args: [
            "-c",
            'printf "\r%s" "###################                                                       27.6%" 1>&2',
          ]
      end.to output(
        "\r###################                                                       27.6%",
      ).to_stderr
    end

    context "when given an executable with spaces and no arguments" do
      let(:executable) { mktmpdir/"App Uninstaller" }

      before do
        executable.write <<~SH
          #!/usr/bin/env bash
          true
        SH

        FileUtils.chmod "+x", executable
      end

      it "does not interpret the executable as a shell line" do
        expect(Class.new.extend(SystemCommand::Mixin).system_command(executable)).to be_a_success
      end
    end

    context "when given arguments with secrets" do
      it "does not leak the secrets" do
        redacted_msg = /#{Regexp.escape("username:******")}/
        expect do
          described_class.run! "curl",
                               args:    %w[--user username:hunter2],
                               verbose: true,
                               debug:   true,
                               secrets: %w[hunter2]
        end.to raise_error(ErrorDuringExecution, redacted_msg).and output(redacted_msg).to_stderr
      end

      it "does not leak the secrets set by environment" do
        redacted_msg = /#{Regexp.escape("username:******")}/
        expect do
          ENV["PASSWORD"] = "hunter2"
          described_class.run! "curl",
                               args:    %w[--user username:hunter2],
                               debug:   true,
                               verbose: true
        end.to raise_error(ErrorDuringExecution, redacted_msg).and output(redacted_msg).to_stderr
      end
    end

    context "when running a process that prints secrets" do
      it "does not leak the secrets" do
        redacted_msg = /#{Regexp.escape("username:******")}/
        expect do
          described_class.run! "echo",
                               args:         %w[username:hunter2],
                               verbose:      true,
                               print_stdout: true,
                               secrets:      %w[hunter2]
        end.to output(redacted_msg).to_stdout
      end

      it "does not leak the secrets set by environment" do
        redacted_msg = /#{Regexp.escape("username:******")}/
        expect do
          ENV["PASSWORD"] = "hunter2"
          described_class.run! "echo",
                               args:         %w[username:hunter2],
                               print_stdout: true,
                               verbose:      true
        end.to output(redacted_msg).to_stdout
      end
    end

    context "when a `SIGINT` handler is set in the parent process" do
      it "is not interrupted" do
        start_time = Time.now

        pid = fork do
          trap("INT") do
            # Ignore SIGINT.
          end

          described_class.run! "sleep", args: [1]

          exit!
        end

        sleep 0.1
        Process.kill("INT", pid)

        Process.waitpid(pid)

        expect(Time.now - start_time).to be >= 1
      end
    end
  end
end
