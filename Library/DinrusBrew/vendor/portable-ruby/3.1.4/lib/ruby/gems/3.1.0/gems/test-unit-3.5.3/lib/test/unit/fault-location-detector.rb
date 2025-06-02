# Copyright (C) 2012  Kouhei Sutou <kou@clear-code.com>
#
# License: Ruby's

require "English"

module Test
  module Unit
    class FaultLocationDetector
      def initialize(fault, code_snippet_fetcher)
        @fault = fault
        @code_snippet_fetcher = code_snippet_fetcher
        extract_fault_information
      end

      def split_backtrace_entry(entry)
        match_data = /\A(.+):(\d+)(?::(.*))?\z/.match(entry)
        return nil if match_data.nil?
        file, line_number, context = match_data.to_a[1..-1]
        line_number = line_number.to_i
        if /\Ain `(.+?)'/ =~ context
          method_name = $1
          if /\Ablock (?:\(.+?\) )?in / =~ method_name
            method_name = $POSTMATCH
          end
        else
          method_name = nil
        end
        [file, line_number, context, method_name]
      end

      def target?(backtrace_entry)
        file, line_number, context, method_name =
          split_backtrace_entry(backtrace_entry)
        _ = context
        return false if file.nil?

        if @fault_source_location
          target_source_location?(file, line_number, method_name)
        elsif @fault_method_name
          target_method?(method_name)
        else
          true
        end
      end

      private
      def target_source_location?(file, line_number, method_name)
        fault_file, fault_line_number = @fault_source_location
        return false unless file.end_with?(fault_file)

        return false if line_number < fault_line_number

        lines = @code_snippet_fetcher.source(file)
        return false if lines.nil?

        base_indent_level = nil
        fault_line_number.step(lines.size) do |current_line_number|
          line = lines[current_line_number - 1]
          current_indent_level = guess_indent_level(line)
          base_indent_level ||= current_indent_level
          return true if current_line_number == line_number

          if current_line_number == fault_line_number
            break if /(?:\send|\})\s*$/ =~ line
          else
            break if current_indent_level == base_indent_level
          end
        end
        false
      end

      def target_method?(method_name)
        @fault_method_name == method_name
      end

      def guess_indent_level(line)
        if /\A(\s*)/ =~ line
          $1.sub(/\t/, " " * 8).count(" ")
        else
          0
        end
      end

      def extract_fault_information
        if @fault.respond_to?(:source_location)
          @fault_source_location = @fault.source_location
        else
          @fault_source_location = nil
        end

        if @fault.respond_to?(:method_name)
          @fault_method_name = @fault.method_name
        else
          @fault_method_name = nil
        end
      end
    end
  end
end
