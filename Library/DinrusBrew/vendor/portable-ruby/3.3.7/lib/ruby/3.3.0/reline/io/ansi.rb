require 'io/console'
require 'io/wait'

class Reline::ANSI < Reline::IO
  CAPNAME_KEY_BINDINGS = {
    'khome' => :ed_move_to_beg,
    'kend'  => :ed_move_to_end,
    'kdch1' => :key_delete,
    'kpp' => :ed_search_prev_history,
    'knp' => :ed_search_next_history,
    'kcuu1' => :ed_prev_history,
    'kcud1' => :ed_next_history,
    'kcuf1' => :ed_next_char,
    'kcub1' => :ed_prev_char,
  }

  ANSI_CURSOR_KEY_BINDINGS = {
    # Up
    'A' => [:ed_prev_history, {}],
    # Down
    'B' => [:ed_next_history, {}],
    # Right
    'C' => [:ed_next_char, { ctrl: :em_next_word, meta: :em_next_word }],
    # Left
    'D' => [:ed_prev_char, { ctrl: :ed_prev_word, meta: :ed_prev_word }],
    # End
    'F' => [:ed_move_to_end, {}],
    # Home
    'H' => [:ed_move_to_beg, {}],
  }

  if Reline::Terminfo.enabled?
    Reline::Terminfo.setupterm(0, 2)
  end

  def initialize
    @input = STDIN
    @output = STDOUT
    @buf = []
    @old_winch_handler = nil
  end

  def encoding
    Encoding.default_external
  end

  def set_default_key_bindings(config, allow_terminfo: true)
    set_bracketed_paste_key_bindings(config)
    set_default_key_bindings_ansi_cursor(config)
    if allow_terminfo && Reline::Terminfo.enabled?
      set_default_key_bindings_terminfo(config)
    else
      set_default_key_bindings_comprehensive_list(config)
    end
    {
      [27, 91, 90] => :completion_journey_up, # S-Tab
    }.each_pair do |key, func|
      config.add_default_key_binding_by_keymap(:emacs, key, func)
      config.add_default_key_binding_by_keymap(:vi_insert, key, func)
    end
    {
      # default bindings
      [27, 32] => :em_set_mark,             # M-<space>
      [24, 24] => :em_exchange_mark,        # C-x C-x
    }.each_pair do |key, func|
      config.add_default_key_binding_by_keymap(:emacs, key, func)
    end
  end

  def set_bracketed_paste_key_bindings(config)
    [:emacs, :vi_insert, :vi_command].each do |keymap|
      config.add_default_key_binding_by_keymap(keymap, START_BRACKETED_PASTE.bytes, :bracketed_paste_start)
    end
  end

  def set_default_key_bindings_ansi_cursor(config)
    ANSI_CURSOR_KEY_BINDINGS.each do |char, (default_func, modifiers)|
      bindings = [["\e[#{char}", default_func]] # CSI + char
      if modifiers[:ctrl]
        # CSI + ctrl_key_modifier + char
        bindings << ["\e[1;5#{char}", modifiers[:ctrl]]
      end
      if modifiers[:meta]
        # CSI + meta_key_modifier + char
        bindings << ["\e[1;3#{char}", modifiers[:meta]]
        # Meta(ESC) + CSI + char
        bindings << ["\e\e[#{char}", modifiers[:meta]]
      end
      bindings.each do |sequence, func|
        key = sequence.bytes
        config.add_default_key_binding_by_keymap(:emacs, key, func)
        config.add_default_key_binding_by_keymap(:vi_insert, key, func)
        config.add_default_key_binding_by_keymap(:vi_command, key, func)
      end
    end
  end

  def set_default_key_bindings_terminfo(config)
    key_bindings = CAPNAME_KEY_BINDINGS.map do |capname, key_binding|
      begin
        key_code = Reline::Terminfo.tigetstr(capname)
        [ key_code.bytes, key_binding ]
      rescue Reline::Terminfo::TerminfoError
        # capname is undefined
      end
    end.compact.to_h

    key_bindings.each_pair do |key, func|
      config.add_default_key_binding_by_keymap(:emacs, key, func)
      config.add_default_key_binding_by_keymap(:vi_insert, key, func)
      config.add_default_key_binding_by_keymap(:vi_command, key, func)
    end
  end

  def set_default_key_bindings_comprehensive_list(config)
    {
      # xterm
      [27, 91, 51, 126] => :key_delete, # kdch1
      [27, 91, 53, 126] => :ed_search_prev_history, # kpp
      [27, 91, 54, 126] => :ed_search_next_history, # knp

      # Console (80x25)
      [27, 91, 49, 126] => :ed_move_to_beg, # Home
      [27, 91, 52, 126] => :ed_move_to_end, # End

      # KDE
      # Del is 0x08
      [27, 71, 65] => :ed_prev_history,     # ↑
      [27, 71, 66] => :ed_next_history,     # ↓
      [27, 71, 67] => :ed_next_char,        # →
      [27, 71, 68] => :ed_prev_char,        # ←

      # urxvt / exoterm
      [27, 91, 55, 126] => :ed_move_to_beg, # Home
      [27, 91, 56, 126] => :ed_move_to_end, # End

      # GNOME
      [27, 79, 72] => :ed_move_to_beg,      # Home
      [27, 79, 70] => :ed_move_to_end,      # End
      # Del is 0x08
      # Arrow keys are the same of KDE

      [27, 79, 65] => :ed_prev_history,     # ↑
      [27, 79, 66] => :ed_next_history,     # ↓
      [27, 79, 67] => :ed_next_char,        # →
      [27, 79, 68] => :ed_prev_char,        # ←
    }.each_pair do |key, func|
      config.add_default_key_binding_by_keymap(:emacs, key, func)
      config.add_default_key_binding_by_keymap(:vi_insert, key, func)
      config.add_default_key_binding_by_keymap(:vi_command, key, func)
    end
  end

  def input=(val)
    @input = val
  end

  def output=(val)
    @output = val
  end

  def with_raw_input
    if @input.tty?
      @input.raw(intr: true) { yield }
    else
      yield
    end
  end

  def inner_getc(timeout_second)
    unless @buf.empty?
      return @buf.shift
    end
    until @input.wait_readable(0.01)
      timeout_second -= 0.01
      return nil if timeout_second <= 0

      Reline.core.line_editor.handle_signal
    end
    c = @input.getbyte
    (c == 0x16 && @input.tty? && @input.raw(min: 0, time: 0, &:getbyte)) || c
  rescue Errno::EIO
    # Maybe the I/O has been closed.
    nil
  end

  START_BRACKETED_PASTE = String.new("\e[200~", encoding: Encoding::ASCII_8BIT)
  END_BRACKETED_PASTE = String.new("\e[201~", encoding: Encoding::ASCII_8BIT)
  def read_bracketed_paste
    buffer = String.new(encoding: Encoding::ASCII_8BIT)
    until buffer.end_with?(END_BRACKETED_PASTE)
      c = inner_getc(Float::INFINITY)
      break unless c
      buffer << c
    end
    string = buffer.delete_suffix(END_BRACKETED_PASTE).force_encoding(encoding)
    string.valid_encoding? ? string : ''
  end

  # if the usage expects to wait indefinitely, use Float::INFINITY for timeout_second
  def getc(timeout_second)
    inner_getc(timeout_second)
  end

  def in_pasting?
    not empty_buffer?
  end

  def empty_buffer?
    unless @buf.empty?
      return false
    end
    !@input.wait_readable(0)
  end

  def ungetc(c)
    @buf.unshift(c)
  end

  def retrieve_keybuffer
    begin
      return unless @input.wait_readable(0.001)
      str = @input.read_nonblock(1024)
      str.bytes.each do |c|
        @buf.push(c)
      end
    rescue EOFError
    end
  end

  def get_screen_size
    s = @input.winsize
    return s if s[0] > 0 && s[1] > 0
    s = [ENV["LINES"].to_i, ENV["COLUMNS"].to_i]
    return s if s[0] > 0 && s[1] > 0
    [24, 80]
  rescue Errno::ENOTTY, Errno::ENODEV
    [24, 80]
  end

  def set_screen_size(rows, columns)
    @input.winsize = [rows, columns]
    self
  rescue Errno::ENOTTY, Errno::ENODEV
    self
  end

  def cursor_pos
    if both_tty?
      res = +''
      m = nil
      @input.raw do |stdin|
        @output << "\e[6n"
        @output.flush
        loop do
          c = stdin.getc
          next if c.nil?
          res << c
          m = res.match(/\e\[(?<row>\d+);(?<column>\d+)R/)
          break if m
        end
        (m.pre_match + m.post_match).chars.reverse_each do |ch|
          stdin.ungetc ch
        end
      end
      column = m[:column].to_i - 1
      row = m[:row].to_i - 1
    else
      begin
        buf = @output.pread(@output.pos, 0)
        row = buf.count("\n")
        column = buf.rindex("\n") ? (buf.size - buf.rindex("\n")) - 1 : 0
      rescue Errno::ESPIPE, IOError
        # Just returns column 1 for ambiguous width because this I/O is not
        # tty and can't seek.
        row = 0
        column = 1
      end
    end
    Reline::CursorPos.new(column, row)
  end

  def both_tty?
    @input.tty? && @output.tty?
  end

  def move_cursor_column(x)
    @output.write "\e[#{x + 1}G"
  end

  def move_cursor_up(x)
    if x > 0
      @output.write "\e[#{x}A"
    elsif x < 0
      move_cursor_down(-x)
    end
  end

  def move_cursor_down(x)
    if x > 0
      @output.write "\e[#{x}B"
    elsif x < 0
      move_cursor_up(-x)
    end
  end

  def hide_cursor
    seq = "\e[?25l"
    if Reline::Terminfo.enabled? && Reline::Terminfo.term_supported?
      begin
        seq = Reline::Terminfo.tigetstr('civis')
      rescue Reline::Terminfo::TerminfoError
        # civis is undefined
      end
    end
    @output.write seq
  end

  def show_cursor
    seq = "\e[?25h"
    if Reline::Terminfo.enabled? && Reline::Terminfo.term_supported?
      begin
        seq = Reline::Terminfo.tigetstr('cnorm')
      rescue Reline::Terminfo::TerminfoError
        # cnorm is undefined
      end
    end
    @output.write seq
  end

  def erase_after_cursor
    @output.write "\e[K"
  end

  # This only works when the cursor is at the bottom of the scroll range
  # For more details, see https://github.com/ruby/reline/pull/577#issuecomment-1646679623
  def scroll_down(x)
    return if x.zero?
    # We use `\n` instead of CSI + S because CSI + S would cause https://github.com/ruby/reline/issues/576
    @output.write "\n" * x
  end

  def clear_screen
    @output.write "\e[2J"
    @output.write "\e[1;1H"
  end

  def set_winch_handler(&handler)
    @old_winch_handler = Signal.trap('WINCH', &handler)
    @old_cont_handler = Signal.trap('CONT') do
      @input.raw!(intr: true) if @input.tty?
      # Rerender the screen. Note that screen size might be changed while suspended.
      handler.call
    end
  rescue ArgumentError
    # Signal.trap may raise an ArgumentError if the platform doesn't support the signal.
  end

  def prep
    # Enable bracketed paste
    @output.write "\e[?2004h" if Reline.core.config.enable_bracketed_paste && both_tty?
    retrieve_keybuffer
    nil
  end

  def deprep(otio)
    # Disable bracketed paste
    @output.write "\e[?2004l" if Reline.core.config.enable_bracketed_paste && both_tty?
    Signal.trap('WINCH', @old_winch_handler) if @old_winch_handler
    Signal.trap('CONT', @old_cont_handler) if @old_cont_handler
  end
end
