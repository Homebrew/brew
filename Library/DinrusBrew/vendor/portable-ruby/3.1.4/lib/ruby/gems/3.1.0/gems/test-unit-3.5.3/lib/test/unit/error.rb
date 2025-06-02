#--
#
# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'test/unit/util/backtracefilter'

module Test
  module Unit

    # Encapsulates an error in a test. Created by
    # Test::Unit::TestCase when it rescues an exception thrown
    # during the processing of a test.
    class Error
      include Util::BacktraceFilter

      attr_reader :test_name, :exception
      attr_reader :method_name

      SINGLE_CHARACTER = 'E'
      LABEL = "Error"

      # Creates a new Error with the given test_name and
      # exception.
      def initialize(test_name, exception, options={})
        @test_name = test_name
        @exception = exception
        @method_name = options[:method_name]
      end

      # Returns a single character representation of an error.
      def single_character_display
        SINGLE_CHARACTER
      end

      def label
        LABEL
      end

      # Returns the message associated with the error.
      def message
        "#{@exception.class.name}: #{@exception.message}"
      end

      # Returns a brief version of the error description.
      def short_display
        "#@test_name: #{message.split("\n")[0]}"
      end

      # Returns a verbose version of the error description.
      def long_display
        backtrace_display = location.join("\n    ")
        "#{label}:\n#@test_name:\n#{message}\n    #{backtrace_display}"
      end

      def location
        @location ||= filter_backtrace(@exception.backtrace)
      end
      alias_method :backtrace, :location # Deprecated

      # Overridden to return long_display.
      def to_s
        long_display
      end

      def critical?
        true
      end
    end

    module ErrorHandler
      class << self
        def included(base)
          base.exception_handler(:handle_all_exception)
        end
      end

      NOT_PASS_THROUGH_EXCEPTIONS = []
      NOT_PASS_THROUGH_EXCEPTION_NAMES = ["Timeout::Error"]
      PASS_THROUGH_EXCEPTIONS = [
        NoMemoryError,
        SignalException,
        Interrupt,
        SystemExit,
      ]
      PASS_THROUGH_EXCEPTION_NAMES = []
      private
      def handle_all_exception(exception)
        return false if pass_through_exception?(exception)

        problem_occurred
        add_error(exception)
        true
      end

      def pass_through_exception?(exception)
        case exception
        when *NOT_PASS_THROUGH_EXCEPTIONS
          return false
        end
        case exception.class.name
        when *NOT_PASS_THROUGH_EXCEPTION_NAMES
          return false
        end

        case exception
        when *PASS_THROUGH_EXCEPTIONS
          return true
        end
        case exception.class.name
        when *PASS_THROUGH_EXCEPTION_NAMES
          return true
        end

        false
      end

      def add_error(exception)
        error = Error.new(name, exception, :method_name => @method_name)
        current_result.add_error(error)
      end
    end

    module TestResultErrorSupport
      attr_reader :errors

      # Records a Test::Unit::Error.
      def add_error(error)
        @errors << error
        notify_fault(error)
        notify_changed
      end

      # Returns the number of errors this TestResult has
      # recorded.
      def error_count
        @errors.size
      end

      def error_occurred?
        not @errors.empty?
      end

      private
      def initialize_containers
        super
        @errors = []
        @summary_generators << :error_summary
        @problem_checkers << :error_occurred?
      end

      def error_summary
        "#{error_count} errors"
      end
    end
  end
end
