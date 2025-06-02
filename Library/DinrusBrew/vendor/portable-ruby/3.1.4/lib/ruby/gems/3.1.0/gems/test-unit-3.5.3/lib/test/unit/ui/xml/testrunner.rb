#--
#
# Author:: Kouhei Sutou
# Copyright::
#   * Copyright (c) 2011 Kouhei Sutou <kou@clear-code.com>
# License:: Ruby license.

require 'erb'
require 'time'
require 'test/unit/ui/testrunner'
require 'test/unit/ui/testrunnermediator'

module Test
  module Unit
    module UI
      module XML

        # Runs a Test::Unit::TestSuite and outputs XML.
        class TestRunner < UI::TestRunner
          include ERB::Util

          # Creates a new TestRunner for running the passed
          # suite. :output option specifies where runner
          # output should go to; defaults to STDOUT.
          def initialize(suite, options={})
            super
            @output = @options[:output] || STDOUT
            if @options[:output_file_descriptor]
              @output = IO.new(@options[:output_file_descriptor], "w")
            end
            @already_outputted = false
            @indent = 0
            @top_level = true
            @current_test = nil
            @current_test_suite = nil
            @already_outputted = false
          end

          private
          def attach_to_mediator
            @mediator.add_listener(TestResult::PASS_ASSERTION,
                                   &method(:result_pass_assertion))
            @mediator.add_listener(TestResult::FAULT,
                                   &method(:result_fault))
            @mediator.add_listener(TestRunnerMediator::STARTED,
                                   &method(:started))
            @mediator.add_listener(TestRunnerMediator::FINISHED,
                                   &method(:finished))
            @mediator.add_listener(TestCase::STARTED_OBJECT,
                                   &method(:test_started))
            @mediator.add_listener(TestCase::FINISHED_OBJECT,
                                   &method(:test_finished))
            @mediator.add_listener(TestSuite::STARTED_OBJECT,
                                   &method(:test_suite_started))
            @mediator.add_listener(TestSuite::FINISHED_OBJECT,
                                   &method(:test_suite_finished))
          end

          def result_pass_assertion(result)
            open_tag("pass-assertion") do
              output_test(@current_test)
            end
          end

          def result_fault(fault)
            open_tag("test-result") do
              open_tag("result") do
                output_test_suite(@current_test_suite)
                output_test(@current_test)
                open_tag("backtrace") do
                  fault.location.each do |entry|
                    file, line, info = entry.split(/:/, 3)
                    open_tag("entry") do
                      add_content("file", file)
                      add_content("line", line)
                      add_content("info", info)
                    end
                  end
                end
                if fault.respond_to?(:expected)
                  add_content("expected", fault.expected)
                end
                if fault.respond_to?(:actual)
                  add_content("actual", fault.actual)
                end
                add_content("detail", fault.message)
                add_content("status", fault.label.downcase)
              end
            end
            @already_outputted = true if fault.critical?
          end

          def started(result)
            @result = result
            output_started
          end

          def output_started
            open_tag("stream")
          end

          def finished(elapsed_time)
            add_content("success", @result.passed?)
            close_tag("stream")
          end

          def test_started(test)
            @already_outputted = false
            @current_test = test
            open_tag("start-test") do
              output_test(test)
            end
          end

          def test_finished(test)
            unless @already_outputted
              open_tag("test-result") do
                output_test(test)
                open_tag("result") do
                  output_test_suite(@current_test_suite)
                  output_test(test)
                  add_content("status", "success")
                end
              end
            end

            open_tag("complete-test") do
              output_test(test)
              add_content("success", test.passed?)
            end
            @current_test = nil
          end

          def test_suite_started(suite)
            @current_test_suite = suite
            if suite.test_case.nil?
              open_tag("ready-test-suite") do
                add_content("n-tests", suite.size)
              end
              open_tag("start-test-suite") do
                output_test_suite(suite)
              end
            else
              open_tag("ready-test-case") do
                output_test_suite(suite)
                add_content("n-tests", suite.size)
              end
              open_tag("start-test-case") do
                output_test_suite(suite)
              end
            end
          end

          def test_suite_finished(suite)
            if suite.test_case.nil?
              open_tag("complete-test-suite") do
                output_test_suite(suite)
                add_content("success", suite.passed?)
              end
            else
              open_tag("complete-test-case") do
                output_test_suite(suite)
                add_content("success", suite.passed?)
              end
            end
            @current_test_suite = nil
          end

          def indent
            " " * @indent
          end

          def open_tag(name)
            @output.puts("#{indent}<#{name}>")
            @indent += 2
            if block_given?
              yield
              close_tag(name)
            end
          end

          def add_content(name, content)
            return if content.nil?
            case content
            when Time
              content = content.iso8601
            end
            @output.puts("#{indent}<#{name}>#{h(content)}</#{name}>")
          end

          def close_tag(name)
            @indent -= 2
            @output.puts("#{indent}</#{name}>")
          end

          def output_test(test)
            open_tag("test") do
              add_content("name", test.method_name)
              add_content("start-time", test.start_time)
              add_content("elapsed", test.elapsed_time)
            end
          end

          def output_test_suite(test_suite)
            test_case = test_suite.test_case
            if test_case.nil?
              open_tag("test-suite") do
                add_content("name", test_suite.name)
                add_content("start-time", test_suite.start_time)
                add_content("elapsed", test_suite.elapsed_time)
              end
            else
              open_tag("test-case") do
                add_content("name", test_suite.name)
                add_content("start-time", test_suite.start_time)
                add_content("elapsed", test_suite.elapsed_time)
              end
            end
          end
        end
      end
    end
  end
end
