require 'io/wait'

class Reline::Dumb < Reline::IO
  RESET_COLOR = '' # Do not send color reset sequence

  def initialize(encoding: nil)
    @input = STDIN
    @buf = []
    @pasting = false
    @encoding = encoding
    @screen_size = [24, 80]
  end

  def dumb?
    true
  end

  def encoding
    if @encoding
      @encoding
    elsif RUBY_PLATFORM =~ /mswin|mingw/
      Encoding::UTF_8
    else
      Encoding::default_external
    end
  end

  def set_default_key_bindings(_)
  end

  def input=(val)
    @input = val
  end

  def with_raw_input
    yield
  end

  def getc(_timeout_second)
    unless @buf.empty?
      return @buf.shift
    end
    c = nil
    loop do
      Reline.core.line_editor.handle_signal
      result = @input.wait_readable(0.1)
      next if result.nil?
      c = @input.read(1)
      break
    end
    c&.ord
  end

  def ungetc(c)
    @buf.unshift(c)
  end

  def get_screen_size
    @screen_size
  end

  def cursor_pos
    Reline::CursorPos.new(1, 1)
  end

  def hide_cursor
  end

  def show_cursor
  end

  def move_cursor_column(val)
  end

  def move_cursor_up(val)
  end

  def move_cursor_down(val)
  end

  def erase_after_cursor
  end

  def scroll_down(val)
  end

  def clear_screen
  end

  def set_screen_size(rows, columns)
    @screen_size = [rows, columns]
  end

  def set_winch_handler(&handler)
  end

  def in_pasting?
    @pasting
  end

  def prep
  end

  def deprep(otio)
  end
end
