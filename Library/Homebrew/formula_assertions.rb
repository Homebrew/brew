# typed: strict
# frozen_string_literal: true

require "utils/output"

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

    sig { params(exp: Object, act: Object, msg: T.nilable(String)).returns(TrueClass) }
    def assert_equal(exp, act, msg = nil)
      # odeprecated "assert_equal(nil, ...)", "assert_nil(...)"
      exp.nil? ? assert_nil(act, msg) : super
    end

    # Returns the output of running cmd and asserts the exit status.
    #
    # @api public
    sig { params(cmd: T.any(Pathname, String), result: Integer).returns(String) }
    def shell_output(cmd, result = 0)
      ohai cmd.to_s
      assert_path_exists cmd, "Pathname '#{cmd}' does not exist!" if cmd.is_a?(Pathname)
      output = `#{cmd}`
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

    # Returns the output of running the cmd on a PTY and optionally asserts the exit status.
    #
    # @api public
    # @param cmd the command to run
    # @param result exit status to assert
    # @param stdin_data string to send to the command's standard input
    # @param stdin_delay seconds to wait before sending `stdin_data`
    # @param timeout seconds to run cmd. A value of 0 will run without any timeout
    # @param winsize the `[rows, columns]` size of PTY. Defaults to `[24, 80]`, i.e. 80x24
    sig {
      params(
        cmd:         T.any(String, Pathname),
        result:      T.nilable(Integer),
        stdin_data:  T.nilable(String),
        stdin_delay: Numeric,
        timeout:     Numeric,
        winsize:     [Integer, Integer],
      ).returns(String)
    }
    def pty_spawn_output(cmd, result = nil, stdin_data: nil, stdin_delay: 0, timeout: 0, winsize: [24, 80])
      require "io/console"
      require "pty"
      require "timeout"

      ohai cmd.to_s
      assert_path_exists cmd, "Pathname '#{cmd}' does not exist!" if cmd.is_a?(Pathname)

      buffer = []
      PTY.spawn(cmd) do |stdout, stdin, pid|
        stdout.winsize = winsize
        stdout.raw!
        stdout_thread = Thread.new do
          stdout.each_char { |char| buffer << char }
        rescue Errno::EIO, IOError
          # Ignore Error::EIO raised by Linux when read is done on a closed pty.
          # Ignore IOError from closing stdout on another thread.
        end

        if stdin_data
          sleep(stdin_delay)
          stdin.write(stdin_data)
        end

        Timeout.timeout(timeout) { stdout_thread.join }
      rescue Timeout::Error
        # Ignore error and let ensure clean up
      ensure
        stdout.close
        stdin.close
        Process.wait(pid)
      end

      output = buffer.join
      assert_equal result, $CHILD_STATUS.exitstatus unless result.nil?
      output
    rescue Minitest::Assertion
      puts output if verbose?
      raise
    end
  end
end
