# typed: true
# frozen_string_literal: true

module Homebrew
  # Helper functions available in formula `test` blocks.
  module Assertions
    include Context

    require "minitest"
    require "minitest/assertions"
    include ::Minitest::Assertions

    attr_writer :assertions

    def assertions
      @assertions ||= 0
    end

    # Returns the output of running cmd, and asserts the exit status.
    # @api public
    def shell_output(cmd, result = 0)
      ohai cmd
      output = `#{cmd}`
      assert_equal result, $CHILD_STATUS.exitstatus
      output
    rescue Minitest::Assertion
      puts output if verbose?
      raise
    end

    # Returns the output of running the cmd with the optional input, and
    # optionally asserts the exit status.
    # @api public
    def pipe_output(cmd, input = nil, result = nil)
      ohai cmd
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
  end
end
