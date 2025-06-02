require 'io/console'
require 'io/wait'
require 'timeout'
require_relative 'terminfo'

class Reline::ANSI
  CAPNAME_KEY_BINDINGS = {
    'khome' => :ed_move_to_beg,
    'kend'  => :ed_move_to_end,
    'kcuu1' => :ed_prev_history,
    'kcud1' => :ed_next_history,
    'kcuf1' => :ed_next_char,
    'kcub1' => :ed_prev_char,
    'cuu' => :ed_prev_history,
    'cud' => :ed_next_history,
    'cuf' => :ed_next_char,
    'cub' => :ed_prev_char,
  }

  if Reline::Terminfo.enabled?
    Reline::Terminfo.setupterm(0, 2)
  end

  def self.encoding
    Encoding.default_external
  end

  def self.win?
    false
  end

  def self.set_default_key_bindings(config)
    if Reline::Terminfo.enabled?
      set_default_key_bindings_terminfo(config)
    else
      set_default_key_bindings_comprehensive_list(config)
    end
    {
      # extended entries of terminfo
      [27, 91, 49, 59, 53, 67] => :em_next_word, # Ctrl+→, extended entry
      [27, 91, 49, 59, 53, 68] => :ed_prev_word, # Ctrl+←, extended entry
      [27, 91, 49, 59, 51, 67] => :em_next_word, # Meta+→, extended entry
      [27, 91, 49, 59, 51, 68] => :ed_prev_word, # Meta+←, extended entry
    }.each_pair do |key, func|
      config.add_default_key_binding_by_keymap(:emacs, key, func)
      config.add_default_key_binding_by_keymap(:vi_insert, key, func)
      config.add_default_key_binding_by_keymap(:vi_command, key, func)
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

  def self.set_default_key_bindings_terminfo(config)
    key_bindings = CAPNAME_KEY_BINDINGS.map do |capname, key_binding|
      begin
        key_code = Reline::Terminfo.tigetstr(capname)
        case capname
        # Escape sequences that omit the move distance and are set to defaults
        # value 1 may be sometimes sent by pressing the arrow-key.
        when 'cuu', 'cud', 'cuf', 'cub'
          [ key_code.sub(/%p1%d/, '').bytes, key_binding ]
        else
          [ key_code.bytes, key_binding ]
        end
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

  def self.set_default_key_bindings_comprehensive_list(config)
    {
      # Console (80x25)
      [27, 91, 49, 126] => :ed_move_to_beg, # Home
      [27, 91, 52, 126] => :ed_move_to_end, # End
      [27, 91, 51, 126] => :key_delete,     # Del
      [27, 91, 65] => :ed_prev_history,     # ↑
      [27, 91, 66] => :ed_next_history,     # ↓
      [27, 91, 67] => :ed_next_char,        # →
      [27, 91, 68] => :ed_prev_char,        # ←

      # KDE
      [27, 91, 72] => :ed_move_to_beg,      # Home
      [27, 91, 70] => :ed_move_to_end,      # End
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

      # iTerm2
      [27, 27, 91, 67] => :em_next_word,    # Option+→, extended entry
      [27, 27, 91, 68] => :ed_prev_word,    # Option+←, extended entry
      [195, 166] => :em_next_word,          # Option+f
      [195, 162] => :ed_prev_word,          # Option+b

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

  @@input = STDIN
  def self.input=(val)
    @@input = val
  end

  @@output = STDOUT
  def self.output=(val)
    @@output = val
  end

  @@buf = []
  def self.inner_getc
    unless @@buf.empty?
      return @@buf.shift
    end
    until c = @@input.raw(intr: true) { @@input.wait_readable(0.1) && @@input.getbyte }
      Reline.core.line_editor.resize
    end
    (c == 0x16 && @@input.raw(min: 0, tim: 0, &:getbyte)) || c
  rescue Errno::EIO
    # Maybe the I/O has been closed.
    nil
  rescue Errno::ENOTTY
    nil
  end

  @@in_bracketed_paste_mode = false
  START_BRACKETED_PASTE = String.new("\e[200~,", encoding: Encoding::ASCII_8BIT)
  END_BRACKETED_PASTE = String.new("\e[200~.", encoding: Encoding::ASCII_8BIT)
  def self.getc_with_bracketed_paste
    buffer = String.new(encoding: Encoding::ASCII_8BIT)
    buffer << inner_getc
    while START_BRACKETED_PASTE.start_with?(buffer) or END_BRACKETED_PASTE.start_with?(buffer) do
      if START_BRACKETED_PASTE == buffer
        @@in_bracketed_paste_mode = true
        return inner_getc
      elsif END_BRACKETED_PASTE == buffer
        @@in_bracketed_paste_mode = false
        ungetc(-1)
        return inner_getc
      end
      begin
        succ_c = nil
        Timeout.timeout(Reline.core.config.keyseq_timeout * 100) {
          succ_c = inner_getc
        }
      rescue Timeout::Error
        break
      else
        buffer << succ_c
      end
    end
    buffer.bytes.reverse_each do |ch|
      ungetc ch
    end
    inner_getc
  end

  def self.getc
    if Reline.core.config.enable_bracketed_paste
      getc_with_bracketed_paste
    else
      inner_getc
    end
  end

  def self.in_pasting?
    @@in_bracketed_paste_mode or (not Reline::IOGate.empty_buffer?)
  end

  def self.empty_buffer?
    unless @@buf.empty?
      return false
    end
    !@@input.wait_readable(0)
  end

  def self.ungetc(c)
    @@buf.unshift(c)
  end

  def self.retrieve_keybuffer
    begin
      return unless @@input.wait_readable(0.001)
      str = @@input.read_nonblock(1024)
      str.bytes.each do |c|
        @@buf.push(c)
      end
    rescue EOFError
    end
  end

  def self.get_screen_size
    s = @@input.winsize
    return s if s[0] > 0 && s[1] > 0
    s = [ENV["LINES"].to_i, ENV["COLUMNS"].to_i]
    return s if s[0] > 0 && s[1] > 0
    [24, 80]
  rescue Errno::ENOTTY
    [24, 80]
  end

  def self.set_screen_size(rows, columns)
    @@input.winsize = [rows, columns]
    self
  rescue Errno::ENOTTY
    self
  end

  def self.cursor_pos
    begin
      res = +''
      m = nil
      @@input.raw do |stdin|
        @@output << "\e[6n"
        @@output.flush
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
    rescue Errno::ENOTTY
      begin
        buf = @@output.pread(@@output.pos, 0)
        row = buf.count("\n")
        column = buf.rindex("\n") ? (buf.size - buf.rindex("\n")) - 1 : 0
      rescue Errno::ESPIPE
        # Just returns column 1 for ambiguous width because this I/O is not
        # tty and can't seek.
        row = 0
        column = 1
      end
    end
    Reline::CursorPos.new(column, row)
  end

  def self.move_cursor_column(x)
    @@output.write "\e[#{x + 1}G"
  end

  def self.move_cursor_up(x)
    if x > 0
      @@output.write "\e[#{x}A"
    elsif x < 0
      move_cursor_down(-x)
    end
  end

  def self.move_cursor_down(x)
    if x > 0
      @@output.write "\e[#{x}B"
    elsif x < 0
      move_cursor_up(-x)
    end
  end

  def self.hide_cursor
    if Reline::Terminfo.enabled?
      begin
        @@output.write Reline::Terminfo.tigetstr('civis')
      rescue Reline::Terminfo::TerminfoError
        # civis is undefined
      end
    else
      # ignored
    end
  end

  def self.show_cursor
    if Reline::Terminfo.enabled?
      begin
        @@output.write Reline::Terminfo.tigetstr('cnorm')
      rescue Reline::Terminfo::TerminfoError
        # cnorm is undefined
      end
    else
      # ignored
    end
  end

  def self.erase_after_cursor
    @@output.write "\e[K"
  end

  def self.scroll_down(x)
    return if x.zero?
    @@output.write "\e[#{x}S"
  end

  def self.clear_screen
    @@output.write "\e[2J"
    @@output.write "\e[1;1H"
  end

  @@old_winch_handler = nil
  def self.set_winch_handler(&handler)
    @@old_winch_handler = Signal.trap('WINCH', &handler)
  end

  def self.prep
    retrieve_keybuffer
    nil
  end

  def self.deprep(otio)
    Signal.trap('WINCH', @@old_winch_handler) if @@old_winch_handler
  end
end
