# typed: strict
# frozen_string_literal: true

require "io/console"
require "utils/popen"

# Various helper functions for interacting with TTYs.
module Tty
  @stream = T.let($stdout, T.nilable(T.any(IO, StringIO)))

  COLOR_CODES = T.let(
    {
      red:     31,
      green:   32,
      yellow:  33,
      blue:    34,
      magenta: 35,
      cyan:    36,
      default: 39,
    }.freeze,
    T::Hash[Symbol, Integer],
  )

  STYLE_CODES = T.let(
    {
      reset:         0,
      bold:          1,
      italic:        3,
      underline:     4,
      strikethrough: 9,
      no_underline:  24,
    }.freeze,
    T::Hash[Symbol, Integer],
  )

  SPECIAL_CODES = T.let(
    {
      up:         "1A",
      down:       "1B",
      right:      "1C",
      left:       "1D",
      erase_line: "K",
      erase_char: "P",
    }.freeze,
    T::Hash[Symbol, String],
  )

  CODES = T.let(COLOR_CODES.merge(STYLE_CODES).freeze, T::Hash[Symbol, Integer])

  TERMINAL_CONTROL_SEQUENCE = %r{
      (?:\e\]|\u009D).*?(?:\a|\e\\|\u009C|\z) |
      (?:\e[P^_X]|\u0090|\u0098|\u009E|\u009F).*?(?:\e\\|\u009C|\z) |
      (?:\e\[|\u009B)[0-?]*[\x20-/]*[@-~] |
      \e[\x20-/]*[@-~] |
      \e |
      [\u0080-\u009F] |
      [\a\r]
    }mx
  private_constant :TERMINAL_CONTROL_SEQUENCE

  BINARY_TERMINAL_CONTROL_SEQUENCE = /
      (?:\x1B\]|\x9D).*?(?:\x07|\x1B\\|\x9C|\z) |
      (?:\x1B[P^_X]|\x90|\x98|\x9E|\x9F).*?(?:\x1B\\|\x9C|\z) |
      (?:\x1B\[|\x9B)[0-?]*[\x20-\x2F]*[@-~] |
      \x1B[\x20-\x2F]*[@-~] |
      \x1B |
      [\x80-\x9F] |
      [\x07\r]
    /mnx
  private_constant :BINARY_TERMINAL_CONTROL_SEQUENCE

  class << self
    sig { params(stream: T.any(IO, StringIO), _block: T.proc.params(arg0: T.any(IO, StringIO)).void).void }
    def with(stream, &_block)
      previous_stream = @stream
      @stream = T.let(stream, T.nilable(T.any(IO, StringIO)))

      yield stream
    ensure
      @stream = T.let(previous_stream, T.nilable(T.any(IO, StringIO)))
    end

    sig { params(string: String).returns(String) }
    def strip_ansi(string)
      if string.ascii_only? || (string.encoding == Encoding::UTF_8 && string.valid_encoding?)
        string.gsub(TERMINAL_CONTROL_SEQUENCE, "")
      else
        string.b.gsub(BINARY_TERMINAL_CONTROL_SEQUENCE, "".b).force_encoding(string.encoding)
      end
    end

    # Simulates a terminal rendering `\r` overwrites (e.g. curl's `--progress-bar`).
    sig { params(string: String).returns(String) }
    def collapse_carriage_returns(string)
      string.split("\n", -1).map do |line|
        # `\r` resets the cursor, it doesn't erase, so keep the last non-empty segment.
        line.split("\r", -1).reject(&:empty?).last || ""
      end.join("\n")
    end

    sig { params(line_count: Integer).returns(String) }
    def move_cursor_up_beginning(line_count)
      "\033[#{line_count}F"
    end

    sig { returns(String) }
    def move_cursor_beginning
      "\033[0G"
    end

    sig { params(line_count: Integer).returns(String) }
    def move_cursor_down(line_count)
      "\033[#{line_count}B"
    end

    sig { returns(String) }
    def clear_to_end
      "\033[K"
    end

    sig { returns(String) }
    def hide_cursor
      "\033[?25l"
    end

    sig { returns(String) }
    def show_cursor
      "\033[?25h"
    end

    sig { returns(String) }
    def begin_synchronized_update
      "\033[?2026h"
    end

    sig { returns(String) }
    def end_synchronized_update
      "\033[?2026l"
    end

    sig { returns(T.nilable([Integer, Integer])) }
    def size
      return @size if defined?(@size)

      @size = T.let(($stdin.winsize if $stdin.tty?), T.nilable([Integer, Integer]))
    rescue IOError, SystemCallError
      @size = nil
    end

    sig { returns(Integer) }
    def height
      @height ||= T.let(
        size&.first || Utils.popen_read_text("/usr/bin/tput", "lines", err: File::NULL).presence&.to_i || 40,
        T.nilable(Integer),
      )
    end

    # Keep in sync with `columns` in Library/Homebrew/utils/tty.sh.
    sig { returns(Integer) }
    def width
      @width ||= T.let(
        size&.second || Utils.popen_read_text("/usr/bin/tput", "cols", err: File::NULL).presence&.to_i || 80,
        T.nilable(Integer),
      )
    end

    sig { params(string: String).returns(String) }
    def truncate(string)
      (w = width).zero? ? string.to_s : (string.to_s[0, w - 4] || "")
    end

    sig { returns(String) }
    def current_escape_sequence
      return "" if @escape_sequence.nil?

      "\033[#{@escape_sequence.join(";")}m"
    end

    sig { void }
    def reset_escape_sequence!
      @escape_sequence = T.let(nil, T.nilable(T::Array[Integer]))
    end

    CODES.each do |name, code|
      define_method(name) do
        @escape_sequence ||= T.let([], T.nilable(T::Array[Integer]))
        @escape_sequence << code
        self
      end
    end

    SPECIAL_CODES.each do |name, code|
      define_method(name) do
        @stream = T.let($stdout, T.nilable(T.any(IO, StringIO)))
        if @stream&.tty?
          "\033[#{code}"
        else
          ""
        end
      end
    end

    sig { returns(String) }
    def to_s
      return "" unless color?

      current_escape_sequence
    ensure
      reset_escape_sequence!
    end

    sig { returns(T::Boolean) }
    def color?
      require "env_config"

      return false if Homebrew::EnvConfig.no_color?
      return true if Homebrew::EnvConfig.color?
      return false if @stream.blank?

      @stream.tty?
    end
  end
end
