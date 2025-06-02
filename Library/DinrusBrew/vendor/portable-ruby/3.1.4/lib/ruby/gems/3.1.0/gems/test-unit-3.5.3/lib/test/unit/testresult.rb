#--
# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'test/unit/util/observable'
require 'test/unit/failure'
require 'test/unit/error'
require 'test/unit/omission'
require 'test/unit/pending'
require 'test/unit/notification'

module Test
  module Unit
    module NullResultContainerInitializer
      private
      def initialize_containers
      end
    end

    # Collects Test::Unit::Failure and Test::Unit::Error so that
    # they can be displayed to the user. To this end, observers
    # can be added to it, allowing the dynamic updating of, say, a
    # UI.
    class TestResult
      include Util::Observable
      include NullResultContainerInitializer
      include TestResultFailureSupport
      include TestResultErrorSupport
      include TestResultPendingSupport
      include TestResultOmissionSupport
      include TestResultNotificationSupport

      FINISHED = name + "::FINISHED"
      CHANGED = name + "::CHANGED"
      PASS_ASSERTION = name + "::PASS_ASSERTION"
      FAULT = name + "::FAULT"

      attr_reader :run_count, :pass_count, :assertion_count, :faults

      attr_accessor :stop_tag

      # Constructs a new, empty TestResult.
      def initialize
        @run_count, @pass_count, @assertion_count = 0, 0, 0
        @summary_generators = []
        @problem_checkers = []
        @faults = []
        @stop_tag = nil
        initialize_containers
      end

      # Records a test run.
      def add_run
        @run_count += 1
        notify_listeners(FINISHED, self)
        notify_changed
      end

      def add_pass
        @pass_count += 1
      end

      # Records an individual assertion.
      def add_assertion
        @assertion_count += 1
        notify_listeners(PASS_ASSERTION, self)
        notify_changed
      end

      # Returns a string contain the recorded runs, assertions,
      # failures and errors in this TestResult.
      def summary
        ["#{run_count} tests",
         "#{assertion_count} assertions",
         *@summary_generators.collect {|generator| __send__(generator)}].join(", ")
      end

      # Returnes a string that shows result status.
      def status
        if passed?
          if pending_count > 0
            "pending"
          elsif omission_count > 0
            "omission"
          elsif notification_count > 0
            "notification"
          else
            "pass"
          end
        elsif error_count > 0
          "error"
        elsif failure_count > 0
          "failure"
        end
      end

      def stop
        throw @stop_tag
      end

      def to_s
        summary
      end

      # Returns whether or not this TestResult represents
      # successful completion.
      def passed?
        @problem_checkers.all? {|checker| not __send__(checker)}
      end

      def pass_percentage
        n_tests = @run_count - omission_count
        if n_tests.zero?
          0
        else
          100.0 * (@pass_count / n_tests.to_f)
        end
      end

      private
      def notify_changed
        notify_listeners(CHANGED, self)
      end

      def notify_fault(fault)
        @faults << fault
        notify_listeners(FAULT, fault)
      end
    end
  end
end
