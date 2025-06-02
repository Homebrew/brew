#--
#
# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'test/unit/util/observable'
require 'test/unit/testresult'

module Test
  module Unit
    module UI

      # Provides an interface to write any given UI against,
      # hopefully making it easy to write new UIs.
      class TestRunnerMediator
        RESET = name + "::RESET"
        STARTED = name + "::STARTED"
        FINISHED = name + "::FINISHED"

        include Util::Observable

        # Creates a new TestRunnerMediator initialized to run
        # the passed suite.
        def initialize(suite)
          @suite = suite
        end

        # Runs the suite the TestRunnerMediator was created
        # with.
        def run
          AutoRunner.need_auto_run = false

          result = create_result

          Test::Unit.run_at_start_hooks
          start_time = Time.now
          begin
            catch do |stop_tag|
              result.stop_tag = stop_tag
              with_listener(result) do
                notify_listeners(RESET, @suite.size)
                notify_listeners(STARTED, result)

                run_suite(result)
              end
            end
          ensure
            elapsed_time = Time.now - start_time
            notify_listeners(FINISHED, elapsed_time)
          end
          Test::Unit.run_at_exit_hooks

          result
        end

        # Just for backward compatibility for NetBeans.
        # NetBeans should not use monkey patching. NetBeans
        # should use runner change public API.
        #
        # See GitHub#38
        #   https://github.com/test-unit/test-unit/issues/38
        def run_suite(result=nil)
          if result.nil?
            run
          else
            @suite.run(result) do |channel, value|
              notify_listeners(channel, value)
            end
          end
        end

        private
        # A factory method to create the result the mediator
        # should run with. Can be overridden by subclasses if
        # one wants to use a different result.
        def create_result
          TestResult.new
        end

        def measure_time
          begin_time = Time.now
          yield
          Time.now - begin_time
        end

        def with_listener(result)
          finished_listener = result.add_listener(TestResult::FINISHED) do |*args|
            notify_listeners(TestResult::FINISHED, *args)
          end
          changed_listener = result.add_listener(TestResult::CHANGED) do |*args|
            notify_listeners(TestResult::CHANGED, *args)
          end
          pass_assertion_listener = result.add_listener(TestResult::PASS_ASSERTION) do |*args|
            notify_listeners(TestResult::PASS_ASSERTION, *args)
          end
          fault_listener = result.add_listener(TestResult::FAULT) do |*args|
            notify_listeners(TestResult::FAULT, *args)
          end

          begin
            yield
          ensure
            result.remove_listener(TestResult::FAULT, fault_listener)
            result.remove_listener(TestResult::CHANGED, changed_listener)
            result.remove_listener(TestResult::FINISHED, finished_listener)
            result.remove_listener(TestResult::PASS_ASSERTION,
                                   pass_assertion_listener)
          end
        end
      end
    end
  end
end
