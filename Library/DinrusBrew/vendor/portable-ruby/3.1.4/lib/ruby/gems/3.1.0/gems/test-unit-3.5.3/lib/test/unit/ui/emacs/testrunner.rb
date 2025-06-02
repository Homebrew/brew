require 'test/unit/ui/console/testrunner'

module Test
  module Unit
    module UI
      module Emacs
        class TestRunner < Console::TestRunner
          private
          def output_setup_end
          end

          def output_started
          end

          def format_fault(fault)
            return super unless fault.respond_to?(:label)
            format_method_name = "format_fault_#{fault.label.downcase}"
            if respond_to?(format_method_name, true)
              __send__(format_method_name, fault)
            else
              super
            end
          end

          def format_fault_failure(failure)
            if failure.location.size == 1
              location = failure.location[0]
              location_display = location.sub(/\A(.+:\d+).*/, ' [\\1]')
            else
              location_display = "\n" + failure.location.join("\n")
            end
            result = "#{failure.label}:\n"
            result += "#{failure.test_name}#{location_display}:\n"
            result += failure.message
            result
          end

          def format_fault_error(error)
            result = "#{error.label}:\n"
            result += "#{error.test_name}:\n"
            result += "#{error.message}\n"
            result += error.backtrace.join("\n")
            result
          end
        end
      end
    end
  end
end
