# typed: strict
# frozen_string_literal: true

module Homebrew
  # Helper functions available in formula `test` blocks.
  module Assertions
    include Context
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

    # Returns the output of running cmd and asserts the exit status.
    #
    # @api public
    sig { params(cmd: T.any(Pathname, String), result: Integer).returns(String) }
    def shell_output(cmd, result = 0)
      ohai cmd
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
