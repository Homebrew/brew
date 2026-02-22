# typed: strict
# frozen_string_literal: true

module Homebrew
  module TestBot
    # Creates Junit report with only required by BuildPulse attributes
    # See https://github.com/Homebrew/homebrew-test-bot/pull/621#discussion_r658712640
    class Junit
      sig { params(tests: T::Array[Test]).void }
      def initialize(tests)
        require "rexml/document"
        require "rexml/xmldecl"
        require "rexml/cdata"

        @tests = tests
        @xml_document = T.let(nil, T.nilable(REXML::Document))
      end

      sig { params(filters: T.nilable(T::Array[String])).void }
      def build(filters: nil)
        filters ||= []

        @xml_document = REXML::Document.new
        @xml_document << REXML::XMLDecl.new
        testsuites = @xml_document.add_element "testsuites"

        @tests.each do |test|
          next if test.steps.empty?

          testsuite = testsuites.add_element "testsuite"
          testsuite.add_attribute "name", "brew-test-bot.#{Utils::Bottles.tag}"
          testsuite.add_attribute "timestamp", T.must(test.steps.fetch(0).start_time).iso8601

          test.steps.each do |step|
            next unless filters.any? { |filter| step.command_short.start_with? filter }

            testcase = testsuite.add_element "testcase"
            testcase.add_attribute "name", step.command_short
            testcase.add_attribute "status", step.status
            testcase.add_attribute "time", step.time
            testcase.add_attribute "timestamp", T.must(step.start_time).iso8601

            next if step.passed?

            elem = testcase.add_element "failure"
            elem.add_attribute "message", "#{step.status}: #{step.command.join(" ")}"
          end
        end
      end

      sig { params(filename: String).void }
      def write(filename)
        output_path = Pathname(filename)
        output_path.unlink if output_path.exist?
        output_path.open("w") do |xml_file|
          pretty_print_indent = 2
          T.must(@xml_document).write(xml_file, pretty_print_indent)
        end
      end
    end
  end
end
