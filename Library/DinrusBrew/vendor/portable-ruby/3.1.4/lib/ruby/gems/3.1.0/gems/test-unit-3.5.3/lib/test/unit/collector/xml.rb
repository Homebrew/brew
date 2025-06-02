#--
#
# Author:: Kouhei Sutou
# Copyright::
#   * Copyright (c) 2011 Kouhei Sutou <kou@clear-code.com>
# License:: Ruby license.

# just test!!! don't use it yet!!!

require 'test/unit/collector'

require 'rexml/document'
require 'rexml/streamlistener'

module Test
  module Unit
    module Collector
      class XML
        include Collector

        def collect(xml_log_path)
          listener = Listener.new
          File.open(xml_log_path) do |xml_log|
            parser = REXML::Parsers::StreamParser.new(xml_log, listener)
            parser.parse
          end
          suite = TestSuite.new("tests in #{xml_log_path}")
          suites = listener.test_suites
          sort(suites).each {|s| add_suite(suite, s)}
          suite
        end

        class Listener
          include REXML::StreamListener

          attr_reader :test_suites
          def initialize
            @ns_stack = [{"xml" => :xml}]
            @tag_stack = [["", :root]]
            @text_stack = ['']
            @state_stack = [:root]
            @values = {}
            @test_suites = []
          end

          def tag_start(name, attributes)
            @text_stack.push('')

            ns = @ns_stack.last.dup
            attrs = {}
            attributes.each do |n, v|
              if /\Axmlns(?:\z|:)/ =~ n
                ns[$POSTMATCH] = v
              else
                attrs[n] = v
              end
            end
            @ns_stack.push(ns)

            _parent_tag = parent_tag
            prefix, local = split_name(name)
            uri = _ns(ns, prefix)
            @tag_stack.push([uri, local])

            state = next_state(@state_stack.last, uri, local)
            @state_stack.push(state)
            @values = {}
            case state
            when :test_suite, :test_case
              # do nothing
            when :test
              @n_pass_assertions = 0 if _parent_tag == "start-test"
            when :backtrace
              @backtrace = []
              @values_backup = @values
            end
          end

          def tag_end(name)
            state = @state_stack.pop
            text = @text_stack.pop
            uri, local = @tag_stack.pop
            no_action_states = [:root, :stream]
            case state
            when *no_action_states
              # do nothing
            when :test_suite
              test_suite_end
            when :complete_test_case
              @test_suites.last << @test_case.suite
            when :test_case
              test_case_end
            when :result
              @result = @values
            when :test
              test_end
            when :pass_assertion
              @n_pass_assertions += 1
            when :backtrace
              @values = @values_backup
              @values["backtrace"] = @backtrace
            when :entry
              file = @values['file']
              line = @values['line']
              info = @values['info']
              @backtrace << "#{file}:#{line}: #{info}"
              @values = {}
            else
              local = normalize_local(local)
              @values[local] = text
            end
            @ns_stack.pop
          end

          def text(data)
            @text_stack.last << data
          end

          private
          def _ns(ns, prefix)
            ns.fetch(prefix, "")
          end

          NAME_SPLIT = /^(?:([\w:][-\w\d.]*):)?([\w:][-\w\d.]*)/
          def split_name(name)
            name =~ NAME_SPLIT
            [$1 || '', $2]
          end

          STATE_TABLE = {
            :root => [:stream],
            :stream => [:ready_test_suite,
                        :start_test_suite,
                        :ready_test_case,
                        :start_test_case,
                        :start_test,
                        :pass_assertion,
                        :test_result,
                        :complete_test,
                        :complete_test_case,
                        :complete_test_suite,
                        :success],
            :ready_test_suite => [:n_tests],
            :start_test_suite => [:test_suite],
            :ready_test_case => [:test_case,
                                 :n_tests],
            :start_test_case => [:test_case],
            :start_test => [:test],
            :pass_assertion => [:test],
            :complete_test => [:test, :success],
            :complete_test_case => [:test_case,
                                    :elapsed,
                                    :success],
            :complete_test_suite => [:test_suite,
                                     :success],
            :test_suite => [:start_time,
                            :elapsed],
            :test_case => [:name,
                           :start_time,
                           :elapsed],
            :test => [:name,
                      :start_time,
                      :elapsed],
            :test_result => [:test,
                             :result],
            :result => [:test_case,
                        :test,
                        :status,
                        :backtrace,
                        :detail],
            :backtrace => [:entry],
            :entry => [:file,
                       :line,
                       :info],
          }
          def next_state(current_state, uri, local)
            local = normalize_local(local)
            valid_elements = STATE_TABLE[current_state]
            if valid_elements.nil?
              raise "unexpected element: #{current_path}"
            end
            next_state = local.to_sym
            unless valid_elements.include?(next_state)
              raise "unexpected element: #{current_path}"
            end
            next_state
          end

          def current_path
            locals = @tag_stack.collect do |uri, local|
              local
            end
            ["", *locals].join("/")
          end

          def normalize_local(local)
            local.gsub(/-/, "_")
          end

          def parent_tag
            @tag_stack.last[1]
          end

          def test_suite_end
            return unless parent_tag == "start-test-suite"
            suite = TestSuite.new
            ["start_time", "elapsed_time", "n_tests"].each do |key|
              if @values.has_key?(key)
                suite.instance_variable_set("@#{key}", @values[key])
              end
            end
            @test_suites << suite
          end

          def test_case_end
            return unless parent_tag == "start-test-case"
            name = @values["name"]
            @test_case = Class.new(TestCase) do
              define_method(:name) do
                name
              end
            end
          end

          def test_end
            return unless parent_tag == "complete-test"
            name = @values["name"]
            n_pass_assertions = @n_pass_assertions
            result = @result
            @test_case.module_eval do
              test
              define_method(name) do
                n_pass_assertions.times do
                  add_assertion
                end
                case result["status"]
                when "omission"
                  add_omission(Omission.new(name,
                                            result["backtrace"],
                                            result["detail"]))
                end
              end
            end
          end
        end
      end
    end
  end
end
