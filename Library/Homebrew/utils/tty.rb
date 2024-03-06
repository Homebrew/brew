# typed: true
# frozen_string_literal: true

require "env_config"

# Various helper functions for interacting with TTYs.
module Tty
  @stream = $stdout

  COLOR_CODES = {
    red:     31,
    green:   32,
    yellow:  33,
    blue:    34,
    magenta: 35,
    cyan:    36,
    default: 39,
  }.freeze

  STYLE_CODES = {
    reset:         0,
    bold:          1,
    italic:        3,
    underline:     4,
    strikethrough: 9,
    no_underline:  24,
  }.freeze

  SPECIAL_CODES = {
    up:         "1A",
    down:       "1B",
    right:      "1C",
    left:       "1D",
    erase_line: "K",
    erase_char: "P",
  }.freeze

  CODES = COLOR_CODES.merge(STYLE_CODES).freeze

  class << self
    sig { params(stream: T.any(IO, StringIO), _block: T.proc.params(arg0: T.any(IO, StringIO)).void).void }
    def with(stream, &_block)
      previous_stream = @stream
      @stream = stream

      yield stream
    ensure
      @stream = previous_stream
    end

    sig { params(string: String).returns(String) }
    def strip_ansi(string)
      string.gsub(/\033\[\d+(;\d+)*m/, "")
    end

    sig { returns(Integer) }
    def width
      @width ||= begin
        _, width = `/bin/stty size 2>/dev/null`.split
        width, = `/usr/bin/tput cols 2>/dev/null`.split if width.to_i.zero?
        width ||= 80
        width.to_i
      end
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
      @escape_sequence = nil
    end

    CODES.each do |name, code|
      define_method(name) do
        @escape_sequence ||= []
        @escape_sequence << code
        self
      end
    end

    SPECIAL_CODES.each do |name, code|
      define_method(name) do
        if @stream.tty?
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
      return false if Homebrew::EnvConfig.no_color?
      return true if Homebrew::EnvConfig.color?

      @stream.tty?
    end
  end
end
