# typed: strict
# frozen_string_literal: true

require "utils/output"
require "utils/popen"

module Homebrew
  # Helper functions available in formula `test` blocks.
  module Assertions
    include Context
    include ::Utils::Output::Mixin
    extend T::Helpers

    requires_ancestor { Kernel }

    require "minitest"
    require "minitest/assertions"
    include ::Minitest::Assertions

    sig { params(assertions: Integer).returns(Integer) }
    attr_writer :assertions

    sig { returns(Integer) }
    def assertions
      @assertions ||= T.let(0, T.nilable(Integer))
    end

    # Runs a command in the background for the duration of a test block.
    # Pass the executable and its arguments separately. For shell setup, use `exec`
    # to replace the shell with the process the helper should clean up.
    # Yields the child process ID and terminates and reaps the child on exit.
    # The block may also reap the child itself.
    # Use a minus-prefixed signal with `pgroup: true` to send both signals to the process group.
    # Sends `KILL` if the child or selected group is still running five seconds after the requested signal.
    # Extra keyword arguments are forwarded to `Process.spawn`.
    #
    # @api public
    sig {
      params(
        executable:    T.any(String, Pathname),
        args:          T.any(String, Pathname),
        signal:        String,
        spawn_options: T.anything,
        block:         T.proc.params(pid: Integer).void,
      ).void
    }
    def with_test_process(executable, *args, signal: "TERM", **spawn_options, &block)
      signal_number = Signal.list.fetch(signal.delete_prefix("-").delete_prefix("SIG"), 0)
      raise ArgumentError, "Unsupported signal: #{signal.inspect}" if signal_number.zero?

      executable = executable.to_s
      pid = Process.spawn([executable, executable], *args, **spawn_options)
      target = signal.start_with?("-") ? -pid : pid
      begin
        yield(pid)
      ensure
        reaped = T.let(reap_test_process(pid, Process::WNOHANG), T::Boolean)
        if target.negative? || !reaped
          begin
            Process.kill(signal_number, target)
          rescue Errno::ESRCH, Errno::EPERM => e
            raise if target.positive? && e.is_a?(Errno::EPERM)

            target = pid
          end

          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
          loop do
            reaped ||= reap_test_process(pid, Process::WNOHANG)
            Process.kill(0, target) if target.negative?
            break if reaped && target.positive?

            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            break if remaining <= 0

            sleep [0.1, remaining].min
          rescue Errno::ESRCH, Errno::EPERM
            # On macOS, probing a group with only zombies may raise EPERM.
            target = pid
          end

          begin
            Process.kill("KILL", target) if target.negative?
          rescue Errno::ESRCH, Errno::EPERM
            target = pid
          end

          unless reaped
            begin
              Process.kill("KILL", pid) if target.positive?
            rescue Errno::ESRCH
              # The child exited between the non-blocking wait and the signal.
            end
            reap_test_process(pid)
          end
        end
      end
    end

    # Returns the output of running cmd and asserts the exit status.
    #
    # @api public
    sig { params(cmd: T.any(Pathname, String), result: Integer).returns(String) }
    def shell_output(cmd, result = 0)
      ohai cmd.to_s
      assert_path_exists cmd, "Pathname '#{cmd}' does not exist!" if cmd.is_a?(Pathname)
      output = if cmd.is_a?(Pathname)
        Utils.popen_read_text("/bin/sh", "-c", 'exec "$1"', "shell_output", cmd.expand_path.to_s, err: :err)
      else
        Utils.popen_read_text("/bin/sh", "-c", cmd, err: :err)
      end
      assert_equal result, $CHILD_STATUS.exitstatus
      output
    rescue Minitest::Assertion
      puts output if verbose?
      raise
    end

    # Returns the output of running the cmd with the optional input and
    # optionally asserts the exit status.
    #
    # @api public
    sig { params(cmd: T.any(String, Pathname), input: T.nilable(String), result: T.nilable(Integer)).returns(String) }
    def pipe_output(cmd, input = nil, result = nil)
      ohai cmd.to_s
      assert_path_exists cmd, "Pathname '#{cmd}' does not exist!" if cmd.is_a?(Pathname)
      output = IO.popen(cmd, "w+") do |pipe|
        pipe.write(input) unless input.nil?
        pipe.close_write
        pipe.read
      end
      assert_equal result, $CHILD_STATUS.exitstatus unless result.nil?
      output
    rescue Minitest::Assertion
      puts output if verbose?
      raise
    end

    private

    sig { params(pid: Integer, flags: Integer).returns(T::Boolean) }
    def reap_test_process(pid, flags = 0)
      !Process.wait(pid, flags).nil?
    rescue Errno::ECHILD
      true
    end
  end
end
