# frozen_string_literal: true

module SyntaxSuggest
  module Capture
    # Shows surrounding kw/end pairs
    #
    # The purpose of showing these extra pairs is due to cases
    # of ambiguity when only one visible line is matched.
    #
    # For example:
    #
    #     1  class Dog
    #     2    def bark
    #     4    def eat
    #     5    end
    #     6  end
    #
    # In this case either line 2 could be missing an `end` or
    # line 4 was an extra line added by mistake (it happens).
    #
    # When we detect the above problem it shows the issue
    # as only being on line 2
    #
    #     2    def bark
    #
    # Showing "neighbor" keyword pairs gives extra context:
    #
    #     2    def bark
    #     4    def eat
    #     5    end
    #
    #
    # Example:
    #
    #   lines = BeforeAfterKeywordEnds.new(
    #     block: block,
    #     code_lines: code_lines
    #   ).call()
    #
    class BeforeAfterKeywordEnds
      def initialize(code_lines:, block:)
        @scanner = ScanHistory.new(code_lines: code_lines, block: block)
        @original_indent = block.current_indent
      end

      def call
        lines = []

        @scanner.scan(
          up: ->(line, kw_count, end_count) {
            next true if line.empty?
            break if line.indent < @original_indent
            next true if line.indent != @original_indent

            # If we're going up and have one complete kw/end pair, stop
            if kw_count != 0 && kw_count == end_count
              lines << line
              break
            end

            lines << line if line.is_kw? || line.is_end?
            true
          },
          down: ->(line, kw_count, end_count) {
            next true if line.empty?
            break if line.indent < @original_indent
            next true if line.indent != @original_indent

            # if we're going down and have one complete kw/end pair,stop
            if kw_count != 0 && kw_count == end_count
              lines << line
              break
            end

            lines << line if line.is_kw? || line.is_end?
            true
          }
        )
        @scanner.stash_changes

        lines
      end
    end
  end
end
