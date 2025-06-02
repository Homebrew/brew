# frozen_string_literal: true

module SyntaxSuggest
  module Capture
    # Shows the context around code provided by "falling" indentation
    #
    # If this is the original code lines:
    #
    #   class OH
    #     def hello
    #       it "foo" do
    #     end
    #   end
    #
    # And this is the line that is captured
    #
    #       it "foo" do
    #
    # It will yield its surrounding context:
    #
    #   class OH
    #     def hello
    #     end
    #   end
    #
    # Example:
    #
    #   FallingIndentLines.new(
    #       block: block,
    #       code_lines: @code_lines
    #   ).call do |line|
    #     @lines_to_output << line
    #   end
    #
    class FallingIndentLines
      def initialize(code_lines:, block:)
        @lines = nil
        @scanner = ScanHistory.new(code_lines: code_lines, block: block)
        @original_indent = block.current_indent
      end

      def call(&yieldable)
        last_indent_up = @original_indent
        last_indent_down = @original_indent

        @scanner.commit_if_changed
        @scanner.scan(
          up: ->(line, _, _) {
            next true if line.empty?

            if line.indent < last_indent_up
              yieldable.call(line)
              last_indent_up = line.indent
            end
            true
          },
          down: ->(line, _, _) {
            next true if line.empty?

            if line.indent < last_indent_down
              yieldable.call(line)
              last_indent_down = line.indent
            end
            true
          }
        )
        @scanner.stash_changes
      end
    end
  end
end
