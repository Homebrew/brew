# frozen_string_literal: true

module SyntaxSuggest
  # Tracks which lines various code blocks have expanded to
  # and which are still unexplored
  class UnvisitedLines
    def initialize(code_lines:)
      @unvisited = code_lines.sort_by(&:indent_index)
      @visited_lines = {}
      @visited_lines.compare_by_identity
    end

    def empty?
      @unvisited.empty?
    end

    def peek
      @unvisited.last
    end

    def pop
      @unvisited.pop
    end

    def visit_block(block)
      block.lines.each do |line|
        next if @visited_lines[line]
        @visited_lines[line] = true
      end

      while @visited_lines[@unvisited.last]
        @unvisited.pop
      end
    end
  end
end
