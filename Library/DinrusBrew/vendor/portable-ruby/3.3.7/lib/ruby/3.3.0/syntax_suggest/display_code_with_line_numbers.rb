# frozen_string_literal: true

module SyntaxSuggest
  # Outputs code with highlighted lines
  #
  # Whatever is passed to this class will be rendered
  # even if it is "marked invisible" any filtering of
  # output should be done before calling this class.
  #
  #   DisplayCodeWithLineNumbers.new(
  #     lines: lines,
  #     highlight_lines: [lines[2], lines[3]]
  #   ).call
  #   # =>
  #       1
  #       2  def cat
  #     > 3    Dir.chdir
  #     > 4    end
  #       5  end
  #       6
  class DisplayCodeWithLineNumbers
    TERMINAL_HIGHLIGHT = "\e[1;3m" # Bold, italics
    TERMINAL_END = "\e[0m"

    def initialize(lines:, highlight_lines: [], terminal: false)
      @lines = Array(lines).sort
      @terminal = terminal
      @highlight_line_hash = Array(highlight_lines).each_with_object({}) { |line, h| h[line] = true }
      @digit_count = @lines.last&.line_number.to_s.length
    end

    def call
      @lines.map do |line|
        format_line(line)
      end.join
    end

    private def format_line(code_line)
      # Handle trailing slash lines
      code_line.original.lines.map.with_index do |contents, i|
        format(
          empty: code_line.empty?,
          number: (code_line.number + i).to_s,
          contents: contents,
          highlight: @highlight_line_hash[code_line]
        )
      end.join
    end

    private def format(contents:, number:, empty:, highlight: false)
      string = +""
      string << if highlight
        "> "
      else
        "  "
      end

      string << number.rjust(@digit_count).to_s
      if empty
        string << contents
      else
        string << "  "
        string << TERMINAL_HIGHLIGHT if @terminal && highlight
        string << contents
        string << TERMINAL_END if @terminal
      end
      string
    end
  end
end
