#--
#
# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

module Test
  module Unit

    # Encapsulates a test failure. Created by Test::Unit::TestCase
    # when an assertion fails.
    class Failure
      attr_reader :test_name, :location, :message
      attr_reader :method_name, :source_location
      attr_reader :expected, :actual, :user_message
      attr_reader :inspected_expected, :inspected_actual

      SINGLE_CHARACTER = 'F'
      LABEL = "Failure"

      # Creates a new Failure with the given location and
      # message.
      def initialize(test_name, location, message, options={})
        @test_name = test_name
        @location = location
        @message = message
        @method_name = options[:method_name]
        @source_location = options[:source_location]
        @expected = options[:expected]
        @actual = options[:actual]
        @inspected_expected = options[:inspected_expected]
        @inspected_actual = options[:inspected_actual]
        @user_message = options[:user_message]
      end
      
      # Returns a single character representation of a failure.
      def single_character_display
        SINGLE_CHARACTER
      end

      def label
        LABEL
      end

      # Returns a brief version of the error description.
      def short_display
        "#@test_name: #{@message.split("\n")[0]}"
      end

      # Returns a verbose version of the error description.
      def long_display
        if location.size == 1
          location_display = location[0].sub(/\A(.+:\d+).*/, ' [\\1]')
        else
          location_display = "\n    [#{location.join("\n     ")}]"
        end
        "#{label}:\n#@test_name#{location_display}:\n#@message"
      end

      # Overridden to return long_display.
      def to_s
        long_display
      end

      def critical?
        true
      end

      def diff
        @diff ||= compute_diff
      end

      private
      def compute_diff
        Assertions::AssertionMessage.delayed_diff(@expected, @actual).inspect
      end
    end

    module FailureHandler
      class << self
        def included(base)
          base.exception_handler(:handle_assertion_failed_error)
        end
      end

      # Report a failure.
      #
      # This is a public API for developers who extend test-unit.
      #
      # @param message [String] The description about the failure.
      # @param backtrace [Array<String>] The backtrace for the failure.
      # @option options [Object] :expected
      #   The expected value of the assertion.
      # @option options [Object] :actual
      #   The actual value of the assertion.
      # @option options [String] :inspected_expected
      #   The inspected expected value of the assertion.
      #   It is used for diff between expected and actual of the failure.
      # @option options [String] :inspected_actual
      #   The inspected actual value of the assertion.
      #   It is used for diff between expected and actual of the failure.
      # @option options [String] :user_message
      #   The message of the assertion from user.
      # @option options [String] :method_name (@method_name)
      #   The method name of the test.
      # @option options [Array<String, Integer>] :source_location
      #   The location where the test is defined. It is the same
      #   format as Proc#source_location. That is, it's an array of
      #   path and and line number where the test definition is
      #   started.
      # @return [void]
      def add_failure(message, backtrace, options={})
        default_options = {
          :method_name => @method_name,
          :source_location => self[:source_location],
        }
        failure = Failure.new(name, filter_backtrace(backtrace), message,
                              default_options.merge(options))
        current_result.add_failure(failure)
      end

      private
      def handle_assertion_failed_error(exception)
        return false unless exception.is_a?(AssertionFailedError)
        problem_occurred
        add_failure(exception.message, exception.backtrace,
                    :expected => exception.expected,
                    :actual => exception.actual,
                    :inspected_expected => exception.inspected_expected,
                    :inspected_actual => exception.inspected_actual,
                    :user_message => exception.user_message)
        true
      end
    end

    module TestResultFailureSupport
      attr_reader :failures

      # Records a Test::Unit::Failure.
      def add_failure(failure)
        @failures << failure
        notify_fault(failure)
        notify_changed
      end

      # Returns the number of failures this TestResult has
      # recorded.
      def failure_count
        @failures.size
      end

      def failure_occurred?
        not @failures.empty?
      end

      private
      def initialize_containers
        super
        @failures = []
        @summary_generators << :failure_summary
        @problem_checkers << :failure_occurred?
      end

      def failure_summary
        "#{failure_count} failures"
      end
    end
  end
end
