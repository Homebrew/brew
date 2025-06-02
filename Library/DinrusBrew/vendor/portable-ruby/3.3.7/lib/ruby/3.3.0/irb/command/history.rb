# frozen_string_literal: true

require "stringio"

require_relative "../pager"

module IRB
  # :stopdoc:

  module Command
    class History < Base
      category "IRB"
      description "Shows the input history. `-g [query]` or `-G [query]` allows you to filter the output."

      def execute(arg)

        if (match = arg&.match(/(-g|-G)\s+(?<grep>.+)\s*\n\z/))
          grep = Regexp.new(match[:grep])
        end

        formatted_inputs = irb_context.io.class::HISTORY.each_with_index.reverse_each.filter_map do |input, index|
          next if grep && !input.match?(grep)

          header = "#{index}: "

          first_line, *other_lines = input.split("\n")
          first_line = "#{header}#{first_line}"

          truncated_lines = other_lines.slice!(1..) # Show 1 additional line (2 total)
          other_lines << "..." if truncated_lines&.any?

          other_lines.map! do |line|
            " " * header.length + line
          end

          [first_line, *other_lines].join("\n") + "\n"
        end

        Pager.page_content(formatted_inputs.join)
      end
    end
  end

  # :startdoc:
end
