require 'reline/kill_ring'
require 'reline/unicode'

require 'tempfile'

class Reline::LineEditor
  # TODO: undo
  # TODO: Use "private alias_method" idiom after drop Ruby 2.5.
  attr_reader :line
  attr_reader :byte_pointer
  attr_accessor :confirm_multiline_termination_proc
  attr_accessor :completion_proc
  attr_accessor :completion_append_character
  attr_accessor :output_modifier_proc
  attr_accessor :prompt_proc
  attr_accessor :auto_indent_proc
  attr_accessor :pre_input_hook
  attr_accessor :dig_perfect_match_proc
  attr_writer :output

  VI_MOTIONS = %i{
    ed_prev_char
    ed_next_char
    vi_zero
    ed_move_to_beg
    ed_move_to_end
    vi_to_column
    vi_next_char
    vi_prev_char
    vi_next_word
    vi_prev_word
    vi_to_next_char
    vi_to_prev_char
    vi_end_word
    vi_next_big_word
    vi_prev_big_word
    vi_end_big_word
    vi_repeat_next_char
    vi_repeat_prev_char
  }

  module CompletionState
    NORMAL = :normal
    COMPLETION = :completion
    MENU = :menu
    JOURNEY = :journey
    MENU_WITH_PERFECT_MATCH = :menu_with_perfect_match
    PERFECT_MATCH = :perfect_match
  end

  CompletionJourneyData = Struct.new('CompletionJourneyData', :preposing, :postposing, :list, :pointer)
  MenuInfo = Struct.new('MenuInfo', :target, :list)

  PROMPT_LIST_CACHE_TIMEOUT = 0.5

  def initialize(config, encoding)
    @config = config
    @completion_append_character = ''
    reset_variables(encoding: encoding)
  end

  def set_pasting_state(in_pasting)
    @in_pasting = in_pasting
  end

  def simplified_rendering?
    if finished?
      false
    elsif @just_cursor_moving and not @rerender_all
      true
    else
      not @rerender_all and not finished? and @in_pasting
    end
  end

  private def check_mode_string
    mode_string = nil
    if @config.show_mode_in_prompt
      if @config.editing_mode_is?(:vi_command)
        mode_string = @config.vi_cmd_mode_string
      elsif @config.editing_mode_is?(:vi_insert)
        mode_string = @config.vi_ins_mode_string
      elsif @config.editing_mode_is?(:emacs)
        mode_string = @config.emacs_mode_string
      else
        mode_string = '?'
      end
    end
    if mode_string != @prev_mode_string
      @rerender_all = true
    end
    @prev_mode_string = mode_string
    mode_string
  end

  private def check_multiline_prompt(buffer)
    if @vi_arg
      prompt = "(arg: #{@vi_arg}) "
      @rerender_all = true
    elsif @searching_prompt
      prompt = @searching_prompt
      @rerender_all = true
    else
      prompt = @prompt
    end
    if simplified_rendering?
      mode_string = check_mode_string
      prompt = mode_string + prompt if mode_string
      return [prompt, calculate_width(prompt, true), [prompt] * buffer.size]
    end
    if @prompt_proc
      use_cached_prompt_list = false
      if @cached_prompt_list
        if @just_cursor_moving
          use_cached_prompt_list = true
        elsif Time.now.to_f < (@prompt_cache_time + PROMPT_LIST_CACHE_TIMEOUT) and buffer.size == @cached_prompt_list.size
          use_cached_prompt_list = true
        end
      end
      use_cached_prompt_list = false if @rerender_all
      if use_cached_prompt_list
        prompt_list = @cached_prompt_list
      else
        prompt_list = @cached_prompt_list = @prompt_proc.(buffer).map { |pr| pr.gsub("\n", "\\n") }
        @prompt_cache_time = Time.now.to_f
      end
      prompt_list.map!{ prompt } if @vi_arg or @searching_prompt
      prompt_list = [prompt] if prompt_list.empty?
      mode_string = check_mode_string
      prompt_list = prompt_list.map{ |pr| mode_string + pr } if mode_string
      prompt = prompt_list[@line_index]
      prompt = prompt_list[0] if prompt.nil?
      prompt = prompt_list.last if prompt.nil?
      if buffer.size > prompt_list.size
        (buffer.size - prompt_list.size).times do
          prompt_list << prompt_list.last
        end
      end
      prompt_width = calculate_width(prompt, true)
      [prompt, prompt_width, prompt_list]
    else
      mode_string = check_mode_string
      prompt = mode_string + prompt if mode_string
      prompt_width = calculate_width(prompt, true)
      [prompt, prompt_width, nil]
    end
  end

  def reset(prompt = '', encoding:)
    @rest_height = (Reline::IOGate.get_screen_size.first - 1) - Reline::IOGate.cursor_pos.y
    @screen_size = Reline::IOGate.get_screen_size
    @screen_height = @screen_size.first
    reset_variables(prompt, encoding: encoding)
    Reline::IOGate.set_winch_handler do
      @resized = true
    end
    if ENV.key?('RELINE_ALT_SCROLLBAR')
      @full_block = '::'
      @upper_half_block = "''"
      @lower_half_block = '..'
      @block_elem_width = 2
    elsif Reline::IOGate.win?
      @full_block = '█'
      @upper_half_block = '▀'
      @lower_half_block = '▄'
      @block_elem_width = 1
    elsif @encoding == Encoding::UTF_8
      @full_block = '█'
      @upper_half_block = '▀'
      @lower_half_block = '▄'
      @block_elem_width = Reline::Unicode.calculate_width('█')
    else
      @full_block = '::'
      @upper_half_block = "''"
      @lower_half_block = '..'
      @block_elem_width = 2
    end
  end

  def resize
    return unless @resized
    @resized = false
    @rest_height = (Reline::IOGate.get_screen_size.first - 1) - Reline::IOGate.cursor_pos.y
    old_screen_size = @screen_size
    @screen_size = Reline::IOGate.get_screen_size
    @screen_height = @screen_size.first
    if old_screen_size.last < @screen_size.last # columns increase
      @rerender_all = true
      rerender
    else
      back = 0
      new_buffer = whole_lines
      prompt, prompt_width, prompt_list = check_multiline_prompt(new_buffer)
      new_buffer.each_with_index do |line, index|
        prompt_width = calculate_width(prompt_list[index], true) if @prompt_proc
        width = prompt_width + calculate_width(line)
        height = calculate_height_by_width(width)
        back += height
      end
      @highest_in_all = back
      @highest_in_this = calculate_height_by_width(prompt_width + @cursor_max)
      @first_line_started_from =
        if @line_index.zero?
          0
        else
          calculate_height_by_lines(@buffer_of_lines[0..(@line_index - 1)], prompt_list || prompt)
        end
      if @prompt_proc
        prompt = prompt_list[@line_index]
        prompt_width = calculate_width(prompt, true)
      end
      calculate_nearest_cursor
      @started_from = calculate_height_by_width(prompt_width + @cursor) - 1
      Reline::IOGate.move_cursor_column((prompt_width + @cursor) % @screen_size.last)
      @highest_in_this = calculate_height_by_width(prompt_width + @cursor_max)
      @rerender_all = true
    end
  end

  def set_signal_handlers
    @old_trap = Signal.trap('INT') {
      clear_dialog
      if @scroll_partial_screen
        move_cursor_down(@screen_height - (@line_index - @scroll_partial_screen) - 1)
      else
        move_cursor_down(@highest_in_all - @line_index - 1)
      end
      Reline::IOGate.move_cursor_column(0)
      scroll_down(1)
      case @old_trap
      when 'DEFAULT', 'SYSTEM_DEFAULT'
        raise Interrupt
      when 'IGNORE'
        # Do nothing
      when 'EXIT'
        exit
      else
        @old_trap.call if @old_trap.respond_to?(:call)
      end
    }
    begin
      @old_tstp_trap = Signal.trap('TSTP') {
        Reline::IOGate.ungetc("\C-z".ord)
        @old_tstp_trap.call if @old_tstp_trap.respond_to?(:call)
      }
    rescue ArgumentError
    end
  end

  def finalize
    Signal.trap('INT', @old_trap)
    begin
      Signal.trap('TSTP', @old_tstp_trap)
    rescue ArgumentError
    end
  end

  def eof?
    @eof
  end

  def reset_variables(prompt = '', encoding:)
    @prompt = prompt.gsub("\n", "\\n")
    @mark_pointer = nil
    @encoding = encoding
    @is_multiline = false
    @finished = false
    @cleared = false
    @rerender_all = false
    @history_pointer = nil
    @kill_ring ||= Reline::KillRing.new
    @vi_clipboard = ''
    @vi_arg = nil
    @waiting_proc = nil
    @waiting_operator_proc = nil
    @waiting_operator_vi_arg = nil
    @completion_journey_data = nil
    @completion_state = CompletionState::NORMAL
    @perfect_matched = nil
    @menu_info = nil
    @first_prompt = true
    @searching_prompt = nil
    @first_char = true
    @add_newline_to_end_of_buffer = false
    @just_cursor_moving = nil
    @cached_prompt_list = nil
    @prompt_cache_time = nil
    @eof = false
    @continuous_insertion_buffer = String.new(encoding: @encoding)
    @scroll_partial_screen = nil
    @prev_mode_string = nil
    @drop_terminate_spaces = false
    @in_pasting = false
    @auto_indent_proc = nil
    @dialogs = []
    @last_key = nil
    @resized = false
    reset_line
  end

  def reset_line
    @cursor = 0
    @cursor_max = 0
    @byte_pointer = 0
    @buffer_of_lines = [String.new(encoding: @encoding)]
    @line_index = 0
    @previous_line_index = nil
    @line = @buffer_of_lines[0]
    @first_line_started_from = 0
    @move_up = 0
    @started_from = 0
    @highest_in_this = 1
    @highest_in_all = 1
    @line_backup_in_history = nil
    @multibyte_buffer = String.new(encoding: 'ASCII-8BIT')
    @check_new_auto_indent = false
  end

  def multiline_on
    @is_multiline = true
  end

  def multiline_off
    @is_multiline = false
  end

  private def calculate_height_by_lines(lines, prompt)
    result = 0
    prompt_list = prompt.is_a?(Array) ? prompt : nil
    lines.each_with_index { |line, i|
      prompt = prompt_list[i] if prompt_list and prompt_list[i]
      result += calculate_height_by_width(calculate_width(prompt, true) + calculate_width(line))
    }
    result
  end

  private def insert_new_line(cursor_line, next_line)
    @line = cursor_line
    @buffer_of_lines.insert(@line_index + 1, String.new(next_line, encoding: @encoding))
    @previous_line_index = @line_index
    @line_index += 1
    @just_cursor_moving = false
  end

  private def calculate_height_by_width(width)
    width.div(@screen_size.last) + 1
  end

  private def split_by_width(str, max_width)
    Reline::Unicode.split_by_width(str, max_width, @encoding)
  end

  private def scroll_down(val)
    if val <= @rest_height
      Reline::IOGate.move_cursor_down(val)
      @rest_height -= val
    else
      Reline::IOGate.move_cursor_down(@rest_height)
      Reline::IOGate.scroll_down(val - @rest_height)
      @rest_height = 0
    end
  end

  private def move_cursor_up(val)
    if val > 0
      Reline::IOGate.move_cursor_up(val)
      @rest_height += val
    elsif val < 0
      move_cursor_down(-val)
    end
  end

  private def move_cursor_down(val)
    if val > 0
      Reline::IOGate.move_cursor_down(val)
      @rest_height -= val
      @rest_height = 0 if @rest_height < 0
    elsif val < 0
      move_cursor_up(-val)
    end
  end

  private def calculate_nearest_cursor(line_to_calc = @line, cursor = @cursor, started_from = @started_from, byte_pointer = @byte_pointer, update = true)
    new_cursor_max = calculate_width(line_to_calc)
    new_cursor = 0
    new_byte_pointer = 0
    height = 1
    max_width = @screen_size.last
    if @config.editing_mode_is?(:vi_command)
      last_byte_size = Reline::Unicode.get_prev_mbchar_size(line_to_calc, line_to_calc.bytesize)
      if last_byte_size > 0
        last_mbchar = line_to_calc.byteslice(line_to_calc.bytesize - last_byte_size, last_byte_size)
        last_width = Reline::Unicode.get_mbchar_width(last_mbchar)
        end_of_line_cursor = new_cursor_max - last_width
      else
      end_of_line_cursor = new_cursor_max
      end
    else
    end_of_line_cursor = new_cursor_max
    end
    line_to_calc.grapheme_clusters.each do |gc|
      mbchar = gc.encode(Encoding::UTF_8)
      mbchar_width = Reline::Unicode.get_mbchar_width(mbchar)
      now = new_cursor + mbchar_width
      if now > end_of_line_cursor or now > cursor
        break
      end
      new_cursor += mbchar_width
      if new_cursor > max_width * height
        height += 1
      end
      new_byte_pointer += gc.bytesize
    end
    new_started_from = height - 1
    if update
      @cursor = new_cursor
      @cursor_max = new_cursor_max
      @started_from = new_started_from
      @byte_pointer = new_byte_pointer
    else
      [new_cursor, new_cursor_max, new_started_from, new_byte_pointer]
    end
  end

  def rerender_all
    @rerender_all = true
    process_insert(force: true)
    rerender
  end

  def rerender
    return if @line.nil?
    if @menu_info
      scroll_down(@highest_in_all - @first_line_started_from)
      @rerender_all = true
    end
    if @menu_info
      show_menu
      @menu_info = nil
    end
    prompt, prompt_width, prompt_list = check_multiline_prompt(whole_lines)
    if @cleared
      clear_screen_buffer(prompt, prompt_list, prompt_width)
      @cleared = false
      return
    end
    if @is_multiline and finished? and @scroll_partial_screen
      # Re-output all code higher than the screen when finished.
      Reline::IOGate.move_cursor_up(@first_line_started_from + @started_from - @scroll_partial_screen)
      Reline::IOGate.move_cursor_column(0)
      @scroll_partial_screen = nil
      prompt, prompt_width, prompt_list = check_multiline_prompt(whole_lines)
      if @previous_line_index
        new_lines = whole_lines(index: @previous_line_index, line: @line)
      else
        new_lines = whole_lines
      end
      modify_lines(new_lines).each_with_index do |line, index|
        @output.write "#{prompt_list ? prompt_list[index] : prompt}#{line}\n"
        Reline::IOGate.erase_after_cursor
      end
      @output.flush
      clear_dialog
      return
    end
    new_highest_in_this = calculate_height_by_width(prompt_width + calculate_width(@line.nil? ? '' : @line))
    rendered = false
    if @add_newline_to_end_of_buffer
      rerender_added_newline(prompt, prompt_width)
      @add_newline_to_end_of_buffer = false
    else
      if @just_cursor_moving and not @rerender_all
        rendered = just_move_cursor
        render_dialog((prompt_width + @cursor) % @screen_size.last)
        @just_cursor_moving = false
        return
      elsif @previous_line_index or new_highest_in_this != @highest_in_this
        rerender_changed_current_line
        @previous_line_index = nil
        rendered = true
      elsif @rerender_all
        rerender_all_lines
        @rerender_all = false
        rendered = true
      else
      end
    end
    if @is_multiline
      if finished?
        # Always rerender on finish because output_modifier_proc may return a different output.
        if @previous_line_index
          new_lines = whole_lines(index: @previous_line_index, line: @line)
        else
          new_lines = whole_lines
        end
        line = modify_lines(new_lines)[@line_index]
        clear_dialog
        prompt, prompt_width, prompt_list = check_multiline_prompt(new_lines)
        render_partial(prompt, prompt_width, line, @first_line_started_from)
        move_cursor_down(@highest_in_all - (@first_line_started_from + @highest_in_this - 1) - 1)
        scroll_down(1)
        Reline::IOGate.move_cursor_column(0)
        Reline::IOGate.erase_after_cursor
      else
        if not rendered and not @in_pasting
          line = modify_lines(whole_lines)[@line_index]
          prompt, prompt_width, prompt_list = check_multiline_prompt(whole_lines)
          render_partial(prompt, prompt_width, line, @first_line_started_from)
        end
        render_dialog((prompt_width + @cursor) % @screen_size.last)
      end
      @buffer_of_lines[@line_index] = @line
      @rest_height = 0 if @scroll_partial_screen
    else
      line = modify_lines(whole_lines)[@line_index]
      render_partial(prompt, prompt_width, line, 0)
      if finished?
        scroll_down(1)
        Reline::IOGate.move_cursor_column(0)
        Reline::IOGate.erase_after_cursor
      end
    end
  end

  class DialogProcScope
    def initialize(line_editor, config, proc_to_exec, context)
      @line_editor = line_editor
      @config = config
      @proc_to_exec = proc_to_exec
      @context = context
      @cursor_pos = Reline::CursorPos.new
    end

    def context
      @context
    end

    def retrieve_completion_block(set_completion_quote_character = false)
      @line_editor.retrieve_completion_block(set_completion_quote_character)
    end

    def call_completion_proc_with_checking_args(pre, target, post)
      @line_editor.call_completion_proc_with_checking_args(pre, target, post)
    end

    def set_dialog(dialog)
      @dialog = dialog
    end

    def dialog
      @dialog
    end

    def set_cursor_pos(col, row)
      @cursor_pos.x = col
      @cursor_pos.y = row
    end

    def set_key(key)
      @key = key
    end

    def key
      @key
    end

    def cursor_pos
      @cursor_pos
    end

    def just_cursor_moving
      @line_editor.instance_variable_get(:@just_cursor_moving)
    end

    def screen_width
      @line_editor.instance_variable_get(:@screen_size).last
    end

    def completion_journey_data
      @line_editor.instance_variable_get(:@completion_journey_data)
    end

    def config
      @config
    end

    def call
      instance_exec(&@proc_to_exec)
    end
  end

  class Dialog
    attr_reader :name, :contents, :width
    attr_accessor :scroll_top, :scrollbar_pos, :pointer, :column, :vertical_offset, :lines_backup, :trap_key

    def initialize(name, config, proc_scope)
      @name = name
      @config = config
      @proc_scope = proc_scope
      @width = nil
      @scroll_top = 0
      @trap_key = nil
    end

    def set_cursor_pos(col, row)
      @proc_scope.set_cursor_pos(col, row)
    end

    def width=(v)
      @width = v
    end

    def contents=(contents)
      @contents = contents
      if contents and @width.nil?
        @width = contents.map{ |line| Reline::Unicode.calculate_width(line, true) }.max
      end
    end

    def call(key)
      @proc_scope.set_dialog(self)
      @proc_scope.set_key(key)
      dialog_render_info = @proc_scope.call
      if @trap_key
        if @trap_key.any?{ |i| i.is_a?(Array) } # multiple trap
          @trap_key.each do |t|
            @config.add_oneshot_key_binding(t, @name)
          end
        elsif @trap_key.is_a?(Array)
          @config.add_oneshot_key_binding(@trap_key, @name)
        elsif @trap_key.is_a?(Integer) or @trap_key.is_a?(Reline::Key)
          @config.add_oneshot_key_binding([@trap_key], @name)
        end
      end
      dialog_render_info
    end
  end

  def add_dialog_proc(name, p, context = nil)
    dialog = Dialog.new(name, @config, DialogProcScope.new(self, @config, p, context))
    if index = @dialogs.find_index { |d| d.name == name }
      @dialogs[index] = dialog
    else
      @dialogs << dialog
    end
  end

  DIALOG_DEFAULT_HEIGHT = 20
  private def render_dialog(cursor_column)
    @dialogs.each do |dialog|
      render_each_dialog(dialog, cursor_column)
    end
  end

  private def padding_space_with_escape_sequences(str, width)
    str + (' ' * (width - calculate_width(str, true)))
  end

  private def render_each_dialog(dialog, cursor_column)
    if @in_pasting
      clear_each_dialog(dialog)
      dialog.contents = nil
      dialog.trap_key = nil
      return
    end
    dialog.set_cursor_pos(cursor_column, @first_line_started_from + @started_from)
    dialog_render_info = dialog.call(@last_key)
    if dialog_render_info.nil? or dialog_render_info.contents.nil? or dialog_render_info.contents.empty?
      dialog.lines_backup = {
        lines: modify_lines(whole_lines),
        line_index: @line_index,
        first_line_started_from: @first_line_started_from,
        started_from: @started_from,
        byte_pointer: @byte_pointer
      }
      clear_each_dialog(dialog)
      dialog.contents = nil
      dialog.trap_key = nil
      return
    end
    old_dialog = dialog.clone
    dialog.contents = dialog_render_info.contents
    pointer = dialog.pointer
    if dialog_render_info.width
      dialog.width = dialog_render_info.width
    else
      dialog.width = dialog.contents.map { |l| calculate_width(l, true) }.max
    end
    height = dialog_render_info.height || DIALOG_DEFAULT_HEIGHT
    height = dialog.contents.size if dialog.contents.size < height
    if dialog.contents.size > height
      if dialog.pointer
        if dialog.pointer < 0
          dialog.scroll_top = 0
        elsif (dialog.pointer - dialog.scroll_top) >= (height - 1)
          dialog.scroll_top = dialog.pointer - (height - 1)
        elsif (dialog.pointer - dialog.scroll_top) < 0
          dialog.scroll_top = dialog.pointer
        end
        pointer = dialog.pointer - dialog.scroll_top
      end
      dialog.contents = dialog.contents[dialog.scroll_top, height]
    end
    if dialog.contents and dialog.scroll_top >= dialog.contents.size
      dialog.scroll_top = dialog.contents.size - height
    end
    if dialog_render_info.scrollbar and dialog_render_info.contents.size > height
      bar_max_height = height * 2
      moving_distance = (dialog_render_info.contents.size - height) * 2
      position_ratio = dialog.scroll_top.zero? ? 0.0 : ((dialog.scroll_top * 2).to_f / moving_distance)
      bar_height = (bar_max_height * ((dialog.contents.size * 2).to_f / (dialog_render_info.contents.size * 2))).floor.to_i
      dialog.scrollbar_pos = ((bar_max_height - bar_height) * position_ratio).floor.to_i
    else
      dialog.scrollbar_pos = nil
    end
    upper_space = @first_line_started_from - @started_from
    dialog.column = dialog_render_info.pos.x
    dialog.width += @block_elem_width if dialog.scrollbar_pos
    diff = (dialog.column + dialog.width) - (@screen_size.last)
    if diff > 0
      dialog.column -= diff
    end
    if (@rest_height - dialog_render_info.pos.y) >= height
      dialog.vertical_offset = dialog_render_info.pos.y + 1
    elsif upper_space >= height
      dialog.vertical_offset = dialog_render_info.pos.y - height
    else
      if (@rest_height - dialog_render_info.pos.y) < height
        scroll_down(height + dialog_render_info.pos.y)
        move_cursor_up(height + dialog_render_info.pos.y)
      end
      dialog.vertical_offset = dialog_render_info.pos.y + 1
    end
    Reline::IOGate.hide_cursor
    if dialog.column < 0
      dialog.column = 0
      dialog.width = @screen_size.last
    end
    reset_dialog(dialog, old_dialog)
    move_cursor_down(dialog.vertical_offset)
    Reline::IOGate.move_cursor_column(dialog.column)
    dialog.contents.each_with_index do |item, i|
      if i == pointer
        bg_color = '45'
      else
        if dialog_render_info.bg_color
          bg_color = dialog_render_info.bg_color
        else
          bg_color = '46'
        end
      end
      str_width = dialog.width - (dialog.scrollbar_pos.nil? ? 0 : @block_elem_width)
      str = padding_space_with_escape_sequences(Reline::Unicode.take_range(item, 0, str_width), str_width)
      @output.write "\e[#{bg_color}m#{str}"
      if dialog.scrollbar_pos and (dialog.scrollbar_pos != old_dialog.scrollbar_pos or dialog.column != old_dialog.column)
        @output.write "\e[37m"
        if dialog.scrollbar_pos <= (i * 2) and (i * 2 + 1) < (dialog.scrollbar_pos + bar_height)
          @output.write @full_block
        elsif dialog.scrollbar_pos <= (i * 2) and (i * 2) < (dialog.scrollbar_pos + bar_height)
          @output.write @upper_half_block
          str += ''
        elsif dialog.scrollbar_pos <= (i * 2 + 1) and (i * 2) < (dialog.scrollbar_pos + bar_height)
          @output.write @lower_half_block
        else
          @output.write ' ' * @block_elem_width
        end
      end
      @output.write "\e[0m"
      Reline::IOGate.move_cursor_column(dialog.column)
      move_cursor_down(1) if i < (dialog.contents.size - 1)
    end
    Reline::IOGate.move_cursor_column(cursor_column)
    move_cursor_up(dialog.vertical_offset + dialog.contents.size - 1)
    Reline::IOGate.show_cursor
    dialog.lines_backup = {
      lines: modify_lines(whole_lines),
      line_index: @line_index,
      first_line_started_from: @first_line_started_from,
      started_from: @started_from,
      byte_pointer: @byte_pointer
    }
  end

  private def reset_dialog(dialog, old_dialog)
    return if dialog.lines_backup.nil? or old_dialog.contents.nil?
    prompt, prompt_width, prompt_list = check_multiline_prompt(dialog.lines_backup[:lines])
    visual_lines = []
    visual_start = nil
    dialog.lines_backup[:lines].each_with_index { |l, i|
      pr = prompt_list ? prompt_list[i] : prompt
      vl, _ = split_by_width(pr + l, @screen_size.last)
      vl.compact!
      if i == dialog.lines_backup[:line_index]
        visual_start = visual_lines.size + dialog.lines_backup[:started_from]
      end
      visual_lines.concat(vl)
    }
    old_y = dialog.lines_backup[:first_line_started_from] + dialog.lines_backup[:started_from]
    y = @first_line_started_from + @started_from
    y_diff = y - old_y
    if (old_y + old_dialog.vertical_offset) < (y + dialog.vertical_offset)
      # rerender top
      move_cursor_down(old_dialog.vertical_offset - y_diff)
      start = visual_start + old_dialog.vertical_offset
      line_num = dialog.vertical_offset - old_dialog.vertical_offset
      line_num.times do |i|
        Reline::IOGate.move_cursor_column(old_dialog.column)
        if visual_lines[start + i].nil?
          s = ' ' * old_dialog.width
        else
          s = Reline::Unicode.take_range(visual_lines[start + i], old_dialog.column, old_dialog.width)
          s = padding_space_with_escape_sequences(s, old_dialog.width)
        end
        @output.write "\e[0m#{s}\e[0m"
        move_cursor_down(1) if i < (line_num - 1)
      end
      move_cursor_up(old_dialog.vertical_offset + line_num - 1 - y_diff)
    end
    if (old_y + old_dialog.vertical_offset + old_dialog.contents.size) > (y + dialog.vertical_offset + dialog.contents.size)
      # rerender bottom
      move_cursor_down(dialog.vertical_offset + dialog.contents.size - y_diff)
      start = visual_start + dialog.vertical_offset + dialog.contents.size
      line_num = (old_dialog.vertical_offset + old_dialog.contents.size) - (dialog.vertical_offset + dialog.contents.size)
      line_num.times do |i|
        Reline::IOGate.move_cursor_column(old_dialog.column)
        if visual_lines[start + i].nil?
          s = ' ' * old_dialog.width
        else
          s = Reline::Unicode.take_range(visual_lines[start + i], old_dialog.column, old_dialog.width)
          s = padding_space_with_escape_sequences(s, old_dialog.width)
        end
        @output.write "\e[0m#{s}\e[0m"
        move_cursor_down(1) if i < (line_num - 1)
      end
      move_cursor_up(dialog.vertical_offset + dialog.contents.size + line_num - 1 - y_diff)
    end
    if old_dialog.column < dialog.column
      # rerender left
      move_cursor_down(old_dialog.vertical_offset - y_diff)
      width = dialog.column - old_dialog.column
      start = visual_start + old_dialog.vertical_offset
      line_num = old_dialog.contents.size
      line_num.times do |i|
        Reline::IOGate.move_cursor_column(old_dialog.column)
        if visual_lines[start + i].nil?
          s = ' ' * width
        else
          s = Reline::Unicode.take_range(visual_lines[start + i], old_dialog.column, width)
          s = padding_space_with_escape_sequences(s, dialog.width)
        end
        @output.write "\e[0m#{s}\e[0m"
        move_cursor_down(1) if i < (line_num - 1)
      end
      move_cursor_up(old_dialog.vertical_offset + line_num - 1 - y_diff)
    end
    if (old_dialog.column + old_dialog.width) > (dialog.column + dialog.width)
      # rerender right
      move_cursor_down(old_dialog.vertical_offset + y_diff)
      width = (old_dialog.column + old_dialog.width) - (dialog.column + dialog.width)
      start = visual_start + old_dialog.vertical_offset
      line_num = old_dialog.contents.size
      line_num.times do |i|
        Reline::IOGate.move_cursor_column(old_dialog.column + dialog.width)
        if visual_lines[start + i].nil?
          s = ' ' * width
        else
          s = Reline::Unicode.take_range(visual_lines[start + i], old_dialog.column + dialog.width, width)
          rerender_width = old_dialog.width - dialog.width
          s = padding_space_with_escape_sequences(s, rerender_width)
        end
        Reline::IOGate.move_cursor_column(dialog.column + dialog.width)
        @output.write "\e[0m#{s}\e[0m"
        move_cursor_down(1) if i < (line_num - 1)
      end
      move_cursor_up(old_dialog.vertical_offset + line_num - 1 + y_diff)
    end
    Reline::IOGate.move_cursor_column((prompt_width + @cursor) % @screen_size.last)
  end

  private def clear_dialog
    @dialogs.each do |dialog|
      clear_each_dialog(dialog)
    end
  end

  private def clear_each_dialog(dialog)
    dialog.trap_key = nil
    return unless dialog.contents
    prompt, prompt_width, prompt_list = check_multiline_prompt(dialog.lines_backup[:lines])
    visual_lines = []
    visual_lines_under_dialog = []
    visual_start = nil
    dialog.lines_backup[:lines].each_with_index { |l, i|
      pr = prompt_list ? prompt_list[i] : prompt
      vl, _ = split_by_width(pr + l, @screen_size.last)
      vl.compact!
      if i == dialog.lines_backup[:line_index]
        visual_start = visual_lines.size + dialog.lines_backup[:started_from] + dialog.vertical_offset
      end
      visual_lines.concat(vl)
    }
    visual_lines_under_dialog = visual_lines[visual_start, dialog.contents.size]
    visual_lines_under_dialog = [] if visual_lines_under_dialog.nil?
    Reline::IOGate.hide_cursor
    move_cursor_down(dialog.vertical_offset)
    dialog_vertical_size = dialog.contents.size
    dialog_vertical_size.times do |i|
      if i < visual_lines_under_dialog.size
        Reline::IOGate.move_cursor_column(dialog.column)
        str = Reline::Unicode.take_range(visual_lines_under_dialog[i], dialog.column, dialog.width)
        str = padding_space_with_escape_sequences(str, dialog.width)
        @output.write "\e[0m#{str}\e[0m"
      else
        Reline::IOGate.move_cursor_column(dialog.column)
        @output.write "\e[0m#{' ' * dialog.width}\e[0m"
      end
      move_cursor_down(1) if i < (dialog_vertical_size - 1)
    end
    move_cursor_up(dialog_vertical_size - 1 + dialog.vertical_offset)
    Reline::IOGate.move_cursor_column((prompt_width + @cursor) % @screen_size.last)
    Reline::IOGate.show_cursor
  end

  private def calculate_scroll_partial_screen(highest_in_all, cursor_y)
    if @screen_height < highest_in_all
      old_scroll_partial_screen = @scroll_partial_screen
      if cursor_y == 0
        @scroll_partial_screen = 0
      elsif cursor_y == (highest_in_all - 1)
        @scroll_partial_screen = highest_in_all - @screen_height
      else
        if @scroll_partial_screen
          if cursor_y <= @scroll_partial_screen
            @scroll_partial_screen = cursor_y
          elsif (@scroll_partial_screen + @screen_height - 1) < cursor_y
            @scroll_partial_screen = cursor_y - (@screen_height - 1)
          end
        else
          if cursor_y > (@screen_height - 1)
            @scroll_partial_screen = cursor_y - (@screen_height - 1)
          else
            @scroll_partial_screen = 0
          end
        end
      end
      if @scroll_partial_screen != old_scroll_partial_screen
        @rerender_all = true
      end
    else
      if @scroll_partial_screen
        @rerender_all = true
      end
      @scroll_partial_screen = nil
    end
  end

  private def rerender_added_newline(prompt, prompt_width)
    scroll_down(1)
    @buffer_of_lines[@previous_line_index] = @line
    @line = @buffer_of_lines[@line_index]
    unless @in_pasting
      render_partial(prompt, prompt_width, @line, @first_line_started_from + @started_from + 1, with_control: false)
    end
    @cursor = @cursor_max = calculate_width(@line)
    @byte_pointer = @line.bytesize
    @highest_in_all += @highest_in_this
    @highest_in_this = calculate_height_by_width(prompt_width + @cursor_max)
    @first_line_started_from += @started_from + 1
    @started_from = calculate_height_by_width(prompt_width + @cursor) - 1
    @previous_line_index = nil
  end

  def just_move_cursor
    prompt, prompt_width, prompt_list = check_multiline_prompt(@buffer_of_lines)
    move_cursor_up(@started_from)
    new_first_line_started_from =
      if @line_index.zero?
        0
      else
        calculate_height_by_lines(@buffer_of_lines[0..(@line_index - 1)], prompt_list || prompt)
      end
    first_line_diff = new_first_line_started_from - @first_line_started_from
    new_cursor, new_cursor_max, new_started_from, new_byte_pointer = calculate_nearest_cursor(@buffer_of_lines[@line_index], @cursor, @started_from, @byte_pointer, false)
    new_started_from = calculate_height_by_width(prompt_width + new_cursor) - 1
    calculate_scroll_partial_screen(@highest_in_all, new_first_line_started_from + new_started_from)
    @previous_line_index = nil
    if @rerender_all
      @line = @buffer_of_lines[@line_index]
      rerender_all_lines
      @rerender_all = false
      true
    else
      @line = @buffer_of_lines[@line_index]
      @first_line_started_from = new_first_line_started_from
      @started_from = new_started_from
      @cursor = new_cursor
      @cursor_max = new_cursor_max
      @byte_pointer = new_byte_pointer
      move_cursor_down(first_line_diff + @started_from)
      Reline::IOGate.move_cursor_column((prompt_width + @cursor) % @screen_size.last)
      false
    end
  end

  private def rerender_changed_current_line
    if @previous_line_index
      new_lines = whole_lines(index: @previous_line_index, line: @line)
    else
      new_lines = whole_lines
    end
    prompt, prompt_width, prompt_list = check_multiline_prompt(new_lines)
    all_height = calculate_height_by_lines(new_lines, prompt_list || prompt)
    diff = all_height - @highest_in_all
    move_cursor_down(@highest_in_all - @first_line_started_from - @started_from - 1)
    if diff > 0
      scroll_down(diff)
      move_cursor_up(all_height - 1)
    elsif diff < 0
      (-diff).times do
        Reline::IOGate.move_cursor_column(0)
        Reline::IOGate.erase_after_cursor
        move_cursor_up(1)
      end
      move_cursor_up(all_height - 1)
    else
      move_cursor_up(all_height - 1)
    end
    @highest_in_all = all_height
    back = render_whole_lines(new_lines, prompt_list || prompt, prompt_width)
    move_cursor_up(back)
    if @previous_line_index
      @buffer_of_lines[@previous_line_index] = @line
      @line = @buffer_of_lines[@line_index]
    end
    @first_line_started_from =
      if @line_index.zero?
        0
      else
        calculate_height_by_lines(@buffer_of_lines[0..(@line_index - 1)], prompt_list || prompt)
      end
    if @prompt_proc
      prompt = prompt_list[@line_index]
      prompt_width = calculate_width(prompt, true)
    end
    move_cursor_down(@first_line_started_from)
    calculate_nearest_cursor
    @started_from = calculate_height_by_width(prompt_width + @cursor) - 1
    move_cursor_down(@started_from)
    Reline::IOGate.move_cursor_column((prompt_width + @cursor) % @screen_size.last)
    @highest_in_this = calculate_height_by_width(prompt_width + @cursor_max)
  end

  private def rerender_all_lines
    move_cursor_up(@first_line_started_from + @started_from)
    Reline::IOGate.move_cursor_column(0)
    back = 0
    new_buffer = whole_lines
    prompt, prompt_width, prompt_list = check_multiline_prompt(new_buffer)
    new_buffer.each_with_index do |line, index|
      prompt_width = calculate_width(prompt_list[index], true) if @prompt_proc
      width = prompt_width + calculate_width(line)
      height = calculate_height_by_width(width)
      back += height
    end
    old_highest_in_all = @highest_in_all
    if @line_index.zero?
      new_first_line_started_from = 0
    else
      new_first_line_started_from = calculate_height_by_lines(new_buffer[0..(@line_index - 1)], prompt_list || prompt)
    end
    new_started_from = calculate_height_by_width(prompt_width + @cursor) - 1
    calculate_scroll_partial_screen(back, new_first_line_started_from + new_started_from)
    if @scroll_partial_screen
      move_cursor_up(@first_line_started_from + @started_from)
      scroll_down(@screen_height - 1)
      move_cursor_up(@screen_height)
      Reline::IOGate.move_cursor_column(0)
    elsif back > old_highest_in_all
      scroll_down(back - 1)
      move_cursor_up(back - 1)
    elsif back < old_highest_in_all
      scroll_down(back)
      Reline::IOGate.erase_after_cursor
      (old_highest_in_all - back - 1).times do
        scroll_down(1)
        Reline::IOGate.erase_after_cursor
      end
      move_cursor_up(old_highest_in_all - 1)
    end
    render_whole_lines(new_buffer, prompt_list || prompt, prompt_width)
    if @prompt_proc
      prompt = prompt_list[@line_index]
      prompt_width = calculate_width(prompt, true)
    end
    @highest_in_this = calculate_height_by_width(prompt_width + @cursor_max)
    @highest_in_all = back
    @first_line_started_from = new_first_line_started_from
    @started_from = new_started_from
    if @scroll_partial_screen
      Reline::IOGate.move_cursor_up(@screen_height - (@first_line_started_from + @started_from - @scroll_partial_screen) - 1)
      Reline::IOGate.move_cursor_column((prompt_width + @cursor) % @screen_size.last)
    else
      move_cursor_down(@first_line_started_from + @started_from - back + 1)
      Reline::IOGate.move_cursor_column((prompt_width + @cursor) % @screen_size.last)
    end
  end

  private def render_whole_lines(lines, prompt, prompt_width)
    rendered_height = 0
    modify_lines(lines).each_with_index do |line, index|
      if prompt.is_a?(Array)
        line_prompt = prompt[index]
        prompt_width = calculate_width(line_prompt, true)
      else
        line_prompt = prompt
      end
      height = render_partial(line_prompt, prompt_width, line, rendered_height, with_control: false)
      if index < (lines.size - 1)
        if @scroll_partial_screen
          if (@scroll_partial_screen - height) < rendered_height and (@scroll_partial_screen + @screen_height - 1) >= (rendered_height + height)
            move_cursor_down(1)
          end
        else
          scroll_down(1)
        end
        rendered_height += height
      else
        rendered_height += height - 1
      end
    end
    rendered_height
  end

  private def render_partial(prompt, prompt_width, line_to_render, this_started_from, with_control: true)
    visual_lines, height = split_by_width(line_to_render.nil? ? prompt : prompt + line_to_render, @screen_size.last)
    cursor_up_from_last_line = 0
    if @scroll_partial_screen
      last_visual_line = this_started_from + (height - 1)
      last_screen_line = @scroll_partial_screen + (@screen_height - 1)
      if (@scroll_partial_screen - this_started_from) >= height
        # Render nothing because this line is before the screen.
        visual_lines = []
      elsif this_started_from > last_screen_line
        # Render nothing because this line is after the screen.
        visual_lines = []
      else
        deleted_lines_before_screen = []
        if @scroll_partial_screen > this_started_from and last_visual_line >= @scroll_partial_screen
          # A part of visual lines are before the screen.
          deleted_lines_before_screen = visual_lines.shift((@scroll_partial_screen - this_started_from) * 2)
          deleted_lines_before_screen.compact!
        end
        if this_started_from <= last_screen_line and last_screen_line < last_visual_line
          # A part of visual lines are after the screen.
          visual_lines.pop((last_visual_line - last_screen_line) * 2)
        end
        move_cursor_up(deleted_lines_before_screen.size - @started_from)
        cursor_up_from_last_line = @started_from - deleted_lines_before_screen.size
      end
    end
    if with_control
      if height > @highest_in_this
        diff = height - @highest_in_this
        scroll_down(diff)
        @highest_in_all += diff
        @highest_in_this = height
        move_cursor_up(diff)
      elsif height < @highest_in_this
        diff = @highest_in_this - height
        @highest_in_all -= diff
        @highest_in_this = height
      end
      move_cursor_up(@started_from)
      @started_from = calculate_height_by_width(prompt_width + @cursor) - 1
      cursor_up_from_last_line = height - 1 - @started_from
    end
    if Reline::Unicode::CSI_REGEXP.match?(prompt + line_to_render)
      @output.write "\e[0m" # clear character decorations
    end
    visual_lines.each_with_index do |line, index|
      Reline::IOGate.move_cursor_column(0)
      if line.nil?
        if calculate_width(visual_lines[index - 1], true) == Reline::IOGate.get_screen_size.last
          # reaches the end of line
          if Reline::IOGate.win? and Reline::IOGate.win_legacy_console?
            # A newline is automatically inserted if a character is rendered at
            # eol on command prompt.
          else
            # When the cursor is at the end of the line and erases characters
            # after the cursor, some terminals delete the character at the
            # cursor position.
            move_cursor_down(1)
            Reline::IOGate.move_cursor_column(0)
          end
        else
          Reline::IOGate.erase_after_cursor
          move_cursor_down(1)
          Reline::IOGate.move_cursor_column(0)
        end
        next
      end
      @output.write line
      if Reline::IOGate.win? and Reline::IOGate.win_legacy_console? and calculate_width(line, true) == Reline::IOGate.get_screen_size.last
        # A newline is automatically inserted if a character is rendered at eol on command prompt.
        @rest_height -= 1 if @rest_height > 0
      end
      @output.flush
      if @first_prompt
        @first_prompt = false
        @pre_input_hook&.call
      end
    end
    unless visual_lines.empty?
      Reline::IOGate.erase_after_cursor
      Reline::IOGate.move_cursor_column(0)
    end
    if with_control
      # Just after rendring, so the cursor is on the last line.
      if finished?
        Reline::IOGate.move_cursor_column(0)
      else
        # Moves up from bottom of lines to the cursor position.
        move_cursor_up(cursor_up_from_last_line)
        # This logic is buggy if a fullwidth char is wrapped because there is only one halfwidth at end of a line.
        Reline::IOGate.move_cursor_column((prompt_width + @cursor) % @screen_size.last)
      end
    end
    height
  end

  private def modify_lines(before)
    return before if before.nil? || before.empty? || simplified_rendering?

    if after = @output_modifier_proc&.call("#{before.join("\n")}\n", complete: finished?)
      after.lines("\n").map { |l| l.chomp('') }
    else
      before
    end
  end

  private def show_menu
    scroll_down(@highest_in_all - @first_line_started_from)
    @rerender_all = true
    @menu_info.list.sort!.each do |item|
      Reline::IOGate.move_cursor_column(0)
      @output.write item
      @output.flush
      scroll_down(1)
    end
    scroll_down(@highest_in_all - 1)
    move_cursor_up(@highest_in_all - 1 - @first_line_started_from)
  end

  private def clear_screen_buffer(prompt, prompt_list, prompt_width)
    Reline::IOGate.clear_screen
    back = 0
    modify_lines(whole_lines).each_with_index do |line, index|
      if @prompt_proc
        pr = prompt_list[index]
        height = render_partial(pr, calculate_width(pr), line, back, with_control: false)
      else
        height = render_partial(prompt, prompt_width, line, back, with_control: false)
      end
      if index < (@buffer_of_lines.size - 1)
        move_cursor_down(1)
        back += height
      end
    end
    move_cursor_up(back)
    move_cursor_down(@first_line_started_from + @started_from)
    @rest_height = (Reline::IOGate.get_screen_size.first - 1) - Reline::IOGate.cursor_pos.y
    Reline::IOGate.move_cursor_column((prompt_width + @cursor) % @screen_size.last)
  end

  def editing_mode
    @config.editing_mode
  end

  private def menu(target, list)
    @menu_info = MenuInfo.new(target, list)
  end

  private def complete_internal_proc(list, is_menu)
    preposing, target, postposing = retrieve_completion_block
    list = list.select { |i|
      if i and not Encoding.compatible?(target.encoding, i.encoding)
        raise Encoding::CompatibilityError, "#{target.encoding.name} is not compatible with #{i.encoding.name}"
      end
      if @config.completion_ignore_case
        i&.downcase&.start_with?(target.downcase)
      else
        i&.start_with?(target)
      end
    }.uniq
    if is_menu
      menu(target, list)
      return nil
    end
    completed = list.inject { |memo, item|
      begin
        memo_mbchars = memo.unicode_normalize.grapheme_clusters
        item_mbchars = item.unicode_normalize.grapheme_clusters
      rescue Encoding::CompatibilityError
        memo_mbchars = memo.grapheme_clusters
        item_mbchars = item.grapheme_clusters
      end
      size = [memo_mbchars.size, item_mbchars.size].min
      result = ''
      size.times do |i|
        if @config.completion_ignore_case
          if memo_mbchars[i].casecmp?(item_mbchars[i])
            result << memo_mbchars[i]
          else
            break
          end
        else
          if memo_mbchars[i] == item_mbchars[i]
            result << memo_mbchars[i]
          else
            break
          end
        end
      end
      result
    }
    [target, preposing, completed, postposing]
  end

  private def complete(list, just_show_list = false)
    case @completion_state
    when CompletionState::NORMAL, CompletionState::JOURNEY
      @completion_state = CompletionState::COMPLETION
    when CompletionState::PERFECT_MATCH
      @dig_perfect_match_proc&.(@perfect_matched)
    end
    if just_show_list
      is_menu = true
    elsif @completion_state == CompletionState::MENU
      is_menu = true
    elsif @completion_state == CompletionState::MENU_WITH_PERFECT_MATCH
      is_menu = true
    else
      is_menu = false
    end
    result = complete_internal_proc(list, is_menu)
    if @completion_state == CompletionState::MENU_WITH_PERFECT_MATCH
      @completion_state = CompletionState::PERFECT_MATCH
    end
    return if result.nil?
    target, preposing, completed, postposing = result
    return if completed.nil?
    if target <= completed and (@completion_state == CompletionState::COMPLETION)
      if list.include?(completed)
        if list.one?
          @completion_state = CompletionState::PERFECT_MATCH
        else
          @completion_state = CompletionState::MENU_WITH_PERFECT_MATCH
        end
        @perfect_matched = completed
      else
        @completion_state = CompletionState::MENU
      end
      if not just_show_list and target < completed
        @line = preposing + completed + completion_append_character.to_s + postposing
        line_to_pointer = preposing + completed + completion_append_character.to_s
        @cursor_max = calculate_width(@line)
        @cursor = calculate_width(line_to_pointer)
        @byte_pointer = line_to_pointer.bytesize
      end
    end
  end

  private def move_completed_list(list, direction)
    case @completion_state
    when CompletionState::NORMAL, CompletionState::COMPLETION,
         CompletionState::MENU, CompletionState::MENU_WITH_PERFECT_MATCH
      @completion_state = CompletionState::JOURNEY
      result = retrieve_completion_block
      return if result.nil?
      preposing, target, postposing = result
      @completion_journey_data = CompletionJourneyData.new(
        preposing, postposing,
        [target] + list.select{ |item| item.start_with?(target) }, 0)
      if @completion_journey_data.list.size == 1
        @completion_journey_data.pointer = 0
      else
        case direction
        when :up
          @completion_journey_data.pointer = @completion_journey_data.list.size - 1
        when :down
          @completion_journey_data.pointer = 1
        end
      end
      @completion_state = CompletionState::JOURNEY
    else
      case direction
      when :up
        @completion_journey_data.pointer -= 1
        if @completion_journey_data.pointer < 0
          @completion_journey_data.pointer = @completion_journey_data.list.size - 1
        end
      when :down
        @completion_journey_data.pointer += 1
        if @completion_journey_data.pointer >= @completion_journey_data.list.size
          @completion_journey_data.pointer = 0
        end
      end
    end
    completed = @completion_journey_data.list[@completion_journey_data.pointer]
    new_line = (@completion_journey_data.preposing + completed + @completion_journey_data.postposing).split("\n")[@line_index]
    @line = new_line.nil? ? String.new(encoding: @encoding) : new_line
    line_to_pointer = (@completion_journey_data.preposing + completed).split("\n").last
    line_to_pointer = String.new(encoding: @encoding) if line_to_pointer.nil?
    @cursor_max = calculate_width(@line)
    @cursor = calculate_width(line_to_pointer)
    @byte_pointer = line_to_pointer.bytesize
  end

  private def run_for_operators(key, method_symbol, &block)
    if @waiting_operator_proc
      if VI_MOTIONS.include?(method_symbol)
        old_cursor, old_byte_pointer = @cursor, @byte_pointer
        @vi_arg = @waiting_operator_vi_arg if @waiting_operator_vi_arg > 1
        block.(true)
        unless @waiting_proc
          cursor_diff, byte_pointer_diff = @cursor - old_cursor, @byte_pointer - old_byte_pointer
          @cursor, @byte_pointer = old_cursor, old_byte_pointer
          @waiting_operator_proc.(cursor_diff, byte_pointer_diff)
        else
          old_waiting_proc = @waiting_proc
          old_waiting_operator_proc = @waiting_operator_proc
          current_waiting_operator_proc = @waiting_operator_proc
          @waiting_proc = proc { |k|
            old_cursor, old_byte_pointer = @cursor, @byte_pointer
            old_waiting_proc.(k)
            cursor_diff, byte_pointer_diff = @cursor - old_cursor, @byte_pointer - old_byte_pointer
            @cursor, @byte_pointer = old_cursor, old_byte_pointer
            current_waiting_operator_proc.(cursor_diff, byte_pointer_diff)
            @waiting_operator_proc = old_waiting_operator_proc
          }
        end
      else
        # Ignores operator when not motion is given.
        block.(false)
      end
      @waiting_operator_proc = nil
      @waiting_operator_vi_arg = nil
      if @vi_arg
        @rerender_all = true
        @vi_arg = nil
      end
    else
      block.(false)
    end
  end

  private def argumentable?(method_obj)
    method_obj and method_obj.parameters.any? { |param| param[0] == :key and param[1] == :arg }
  end

  private def inclusive?(method_obj)
    # If a motion method with the keyword argument "inclusive" follows the
    # operator, it must contain the character at the cursor position.
    method_obj and method_obj.parameters.any? { |param| param[0] == :key and param[1] == :inclusive }
  end

  def wrap_method_call(method_symbol, method_obj, key, with_operator = false)
    if @config.editing_mode_is?(:emacs, :vi_insert) and @waiting_proc.nil? and @waiting_operator_proc.nil?
      not_insertion = method_symbol != :ed_insert
      process_insert(force: not_insertion)
    end
    if @vi_arg and argumentable?(method_obj)
      if with_operator and inclusive?(method_obj)
        method_obj.(key, arg: @vi_arg, inclusive: true)
      else
        method_obj.(key, arg: @vi_arg)
      end
    else
      if with_operator and inclusive?(method_obj)
        method_obj.(key, inclusive: true)
      else
        method_obj.(key)
      end
    end
  end

  private def process_key(key, method_symbol)
    if method_symbol and respond_to?(method_symbol, true)
      method_obj = method(method_symbol)
    else
      method_obj = nil
    end
    if method_symbol and key.is_a?(Symbol)
      if @vi_arg and argumentable?(method_obj)
        run_for_operators(key, method_symbol) do |with_operator|
          wrap_method_call(method_symbol, method_obj, key, with_operator)
        end
      else
        wrap_method_call(method_symbol, method_obj, key) if method_obj
      end
      @kill_ring.process
      if @vi_arg
        @rerender_al = true
        @vi_arg = nil
      end
    elsif @vi_arg
      if key.chr =~ /[0-9]/
        ed_argument_digit(key)
      else
        if argumentable?(method_obj)
          run_for_operators(key, method_symbol) do |with_operator|
            wrap_method_call(method_symbol, method_obj, key, with_operator)
          end
        elsif @waiting_proc
          @waiting_proc.(key)
        elsif method_obj
          wrap_method_call(method_symbol, method_obj, key)
        else
          ed_insert(key) unless @config.editing_mode_is?(:vi_command)
        end
        @kill_ring.process
        if @vi_arg
          @rerender_all = true
          @vi_arg = nil
        end
      end
    elsif @waiting_proc
      @waiting_proc.(key)
      @kill_ring.process
    elsif method_obj
      if method_symbol == :ed_argument_digit
        wrap_method_call(method_symbol, method_obj, key)
      else
        run_for_operators(key, method_symbol) do |with_operator|
          wrap_method_call(method_symbol, method_obj, key, with_operator)
        end
      end
      @kill_ring.process
    else
      ed_insert(key) unless @config.editing_mode_is?(:vi_command)
    end
  end

  private def normal_char(key)
    method_symbol = method_obj = nil
    if key.combined_char.is_a?(Symbol)
      process_key(key.combined_char, key.combined_char)
      return
    end
    @multibyte_buffer << key.combined_char
    if @multibyte_buffer.size > 1
      if @multibyte_buffer.dup.force_encoding(@encoding).valid_encoding?
        process_key(@multibyte_buffer.dup.force_encoding(@encoding), nil)
        @multibyte_buffer.clear
      else
        # invalid
        return
      end
    else # single byte
      return if key.char >= 128 # maybe, first byte of multi byte
      method_symbol = @config.editing_mode.get_method(key.combined_char)
      if key.with_meta and method_symbol == :ed_unassigned
        # split ESC + key
        method_symbol = @config.editing_mode.get_method("\e".ord)
        process_key("\e".ord, method_symbol)
        method_symbol = @config.editing_mode.get_method(key.char)
        process_key(key.char, method_symbol)
      else
        process_key(key.combined_char, method_symbol)
      end
      @multibyte_buffer.clear
    end
    if @config.editing_mode_is?(:vi_command) and @cursor > 0 and @cursor == @cursor_max
      byte_size = Reline::Unicode.get_prev_mbchar_size(@line, @byte_pointer)
      @byte_pointer -= byte_size
      mbchar = @line.byteslice(@byte_pointer, byte_size)
      width = Reline::Unicode.get_mbchar_width(mbchar)
      @cursor -= width
    end
  end

  def input_key(key)
    @last_key = key
    @config.reset_oneshot_key_bindings
    @dialogs.each do |dialog|
      if key.char.instance_of?(Symbol) and key.char == dialog.name
        return
      end
    end
    @just_cursor_moving = nil
    if key.char.nil?
      if @first_char
        @line = nil
      end
      finish
      return
    end
    old_line = @line.dup
    @first_char = false
    completion_occurs = false
    if @config.editing_mode_is?(:emacs, :vi_insert) and key.char == "\C-i".ord
      unless @config.disable_completion
        result = call_completion_proc
        if result.is_a?(Array)
          completion_occurs = true
          process_insert
          if @config.autocompletion
            move_completed_list(result, :down)
          else
            complete(result)
          end
        end
      end
    elsif @config.editing_mode_is?(:emacs, :vi_insert) and key.char == :completion_journey_up
      if not @config.disable_completion and @config.autocompletion
        result = call_completion_proc
        if result.is_a?(Array)
          completion_occurs = true
          process_insert
          move_completed_list(result, :up)
        end
      end
    elsif not @config.disable_completion and @config.editing_mode_is?(:vi_insert) and ["\C-p".ord, "\C-n".ord].include?(key.char)
      unless @config.disable_completion
        result = call_completion_proc
        if result.is_a?(Array)
          completion_occurs = true
          process_insert
          move_completed_list(result, "\C-p".ord == key.char ? :up : :down)
        end
      end
    elsif Symbol === key.char and respond_to?(key.char, true)
      process_key(key.char, key.char)
    else
      normal_char(key)
    end
    unless completion_occurs
      @completion_state = CompletionState::NORMAL
      @completion_journey_data = nil
    end
    if not @in_pasting and @just_cursor_moving.nil?
      if @previous_line_index and @buffer_of_lines[@previous_line_index] == @line
        @just_cursor_moving = true
      elsif @previous_line_index.nil? and @buffer_of_lines[@line_index] == @line and old_line == @line
        @just_cursor_moving = true
      else
        @just_cursor_moving = false
      end
    else
      @just_cursor_moving = false
    end
    if @is_multiline and @auto_indent_proc and not simplified_rendering?
      process_auto_indent
    end
  end

  def call_completion_proc
    result = retrieve_completion_block(true)
    pre, target, post = result
    result = call_completion_proc_with_checking_args(pre, target, post)
    Reline.core.instance_variable_set(:@completion_quote_character, nil)
    result
  end

  def call_completion_proc_with_checking_args(pre, target, post)
    if @completion_proc and target
      argnum = @completion_proc.parameters.inject(0) { |result, item|
        case item.first
        when :req, :opt
          result + 1
        when :rest
          break 3
        end
      }
      case argnum
      when 1
        result = @completion_proc.(target)
      when 2
        result = @completion_proc.(target, pre)
      when 3..Float::INFINITY
        result = @completion_proc.(target, pre, post)
      end
    end
    result
  end

  private def process_auto_indent
    return if not @check_new_auto_indent and @previous_line_index # move cursor up or down
    if @check_new_auto_indent and @previous_line_index and @previous_line_index > 0 and @line_index > @previous_line_index
      # Fix indent of a line when a newline is inserted to the next
      new_lines = whole_lines(index: @previous_line_index, line: @line)
      new_indent = @auto_indent_proc.(new_lines[0..-3].push(''), @line_index - 1, 0, true)
      md = @line.match(/\A */)
      prev_indent = md[0].count(' ')
      @line = ' ' * new_indent + @line.lstrip

      new_indent = nil
      result = @auto_indent_proc.(new_lines[0..-2], @line_index - 1, (new_lines[-2].size + 1), false)
      if result
        new_indent = result
      end
      if new_indent&.>= 0
        @line = ' ' * new_indent + @line.lstrip
      end
    end
    if @previous_line_index
      new_lines = whole_lines(index: @previous_line_index, line: @line)
    else
      new_lines = whole_lines
    end
    new_indent = @auto_indent_proc.(new_lines, @line_index, @byte_pointer, @check_new_auto_indent)
    new_indent = @cursor_max if new_indent&.> @cursor_max
    if new_indent&.>= 0
      md = new_lines[@line_index].match(/\A */)
      prev_indent = md[0].count(' ')
      if @check_new_auto_indent
        @buffer_of_lines[@line_index] = ' ' * new_indent + @buffer_of_lines[@line_index].lstrip
        @cursor = new_indent
        @byte_pointer = new_indent
      else
        @line = ' ' * new_indent + @line.lstrip
        @cursor += new_indent - prev_indent
        @byte_pointer += new_indent - prev_indent
      end
    end
    @check_new_auto_indent = false
  end

  def retrieve_completion_block(set_completion_quote_character = false)
    if Reline.completer_word_break_characters.empty?
      word_break_regexp = nil
    else
      word_break_regexp = /\A[#{Regexp.escape(Reline.completer_word_break_characters)}]/
    end
    if Reline.completer_quote_characters.empty?
      quote_characters_regexp = nil
    else
      quote_characters_regexp = /\A[#{Regexp.escape(Reline.completer_quote_characters)}]/
    end
    before = @line.byteslice(0, @byte_pointer)
    rest = nil
    break_pointer = nil
    quote = nil
    closing_quote = nil
    escaped_quote = nil
    i = 0
    while i < @byte_pointer do
      slice = @line.byteslice(i, @byte_pointer - i)
      unless slice.valid_encoding?
        i += 1
        next
      end
      if quote and slice.start_with?(closing_quote)
        quote = nil
        i += 1
        rest = nil
      elsif quote and slice.start_with?(escaped_quote)
        # skip
        i += 2
      elsif quote_characters_regexp and slice =~ quote_characters_regexp # find new "
        rest = $'
        quote = $&
        closing_quote = /(?!\\)#{Regexp.escape(quote)}/
        escaped_quote = /\\#{Regexp.escape(quote)}/
        i += 1
        break_pointer = i - 1
      elsif word_break_regexp and not quote and slice =~ word_break_regexp
        rest = $'
        i += 1
        before = @line.byteslice(i, @byte_pointer - i)
        break_pointer = i
      else
        i += 1
      end
    end
    postposing = @line.byteslice(@byte_pointer, @line.bytesize - @byte_pointer)
    if rest
      preposing = @line.byteslice(0, break_pointer)
      target = rest
      if set_completion_quote_character and quote
        Reline.core.instance_variable_set(:@completion_quote_character, quote)
        if postposing !~ /(?!\\)#{Regexp.escape(quote)}/ # closing quote
          insert_text(quote)
        end
      end
    else
      preposing = ''
      if break_pointer
        preposing = @line.byteslice(0, break_pointer)
      else
        preposing = ''
      end
      target = before
    end
    if @is_multiline
      if @previous_line_index
        lines = whole_lines(index: @previous_line_index, line: @line)
      else
        lines = whole_lines
      end
      if @line_index > 0
        preposing = lines[0..(@line_index - 1)].join("\n") + "\n" + preposing
      end
      if (lines.size - 1) > @line_index
        postposing = postposing + "\n" + lines[(@line_index + 1)..-1].join("\n")
      end
    end
    [preposing.encode(@encoding), target.encode(@encoding), postposing.encode(@encoding)]
  end

  def confirm_multiline_termination
    temp_buffer = @buffer_of_lines.dup
    if @previous_line_index and @line_index == (@buffer_of_lines.size - 1)
      temp_buffer[@previous_line_index] = @line
    else
      temp_buffer[@line_index] = @line
    end
    @confirm_multiline_termination_proc.(temp_buffer.join("\n") + "\n")
  end

  def insert_text(text)
    width = calculate_width(text)
    if @cursor == @cursor_max
      @line += text
    else
      @line = byteinsert(@line, @byte_pointer, text)
    end
    @byte_pointer += text.bytesize
    @cursor += width
    @cursor_max += width
  end

  def delete_text(start = nil, length = nil)
    if start.nil? and length.nil?
      if @is_multiline
        if @buffer_of_lines.size == 1
          @line&.clear
          @byte_pointer = 0
          @cursor = 0
          @cursor_max = 0
        elsif @line_index == (@buffer_of_lines.size - 1) and @line_index > 0
          @buffer_of_lines.pop
          @line_index -= 1
          @line = @buffer_of_lines[@line_index]
          @byte_pointer = 0
          @cursor = 0
          @cursor_max = calculate_width(@line)
        elsif @line_index < (@buffer_of_lines.size - 1)
          @buffer_of_lines.delete_at(@line_index)
          @line = @buffer_of_lines[@line_index]
          @byte_pointer = 0
          @cursor = 0
          @cursor_max = calculate_width(@line)
        end
      else
        @line&.clear
        @byte_pointer = 0
        @cursor = 0
        @cursor_max = 0
      end
    elsif not start.nil? and not length.nil?
      if @line
        before = @line.byteslice(0, start)
        after = @line.byteslice(start + length, @line.bytesize)
        @line = before + after
        @byte_pointer = @line.bytesize if @byte_pointer > @line.bytesize
        str = @line.byteslice(0, @byte_pointer)
        @cursor = calculate_width(str)
        @cursor_max = calculate_width(@line)
      end
    elsif start.is_a?(Range)
      range = start
      first = range.first
      last = range.last
      last = @line.bytesize - 1 if last > @line.bytesize
      last += @line.bytesize if last < 0
      first += @line.bytesize if first < 0
      range = range.exclude_end? ? first...last : first..last
      @line = @line.bytes.reject.with_index{ |c, i| range.include?(i) }.map{ |c| c.chr(Encoding::ASCII_8BIT) }.join.force_encoding(@encoding)
      @byte_pointer = @line.bytesize if @byte_pointer > @line.bytesize
      str = @line.byteslice(0, @byte_pointer)
      @cursor = calculate_width(str)
      @cursor_max = calculate_width(@line)
    else
      @line = @line.byteslice(0, start)
      @byte_pointer = @line.bytesize if @byte_pointer > @line.bytesize
      str = @line.byteslice(0, @byte_pointer)
      @cursor = calculate_width(str)
      @cursor_max = calculate_width(@line)
    end
  end

  def byte_pointer=(val)
    @byte_pointer = val
    str = @line.byteslice(0, @byte_pointer)
    @cursor = calculate_width(str)
    @cursor_max = calculate_width(@line)
  end

  def whole_lines(index: @line_index, line: @line)
    temp_lines = @buffer_of_lines.dup
    temp_lines[index] = line
    temp_lines
  end

  def whole_buffer
    if @buffer_of_lines.size == 1 and @line.nil?
      nil
    else
      if @previous_line_index
        whole_lines(index: @previous_line_index, line: @line).join("\n")
      else
        whole_lines.join("\n")
      end
    end
  end

  def finished?
    @finished
  end

  def finish
    @finished = true
    @rerender_all = true
    @config.reset
  end

  private def byteslice!(str, byte_pointer, size)
    new_str = str.byteslice(0, byte_pointer)
    new_str << str.byteslice(byte_pointer + size, str.bytesize)
    [new_str, str.byteslice(byte_pointer, size)]
  end

  private def byteinsert(str, byte_pointer, other)
    new_str = str.byteslice(0, byte_pointer)
    new_str << other
    new_str << str.byteslice(byte_pointer, str.bytesize)
    new_str
  end

  private def calculate_width(str, allow_escape_code = false)
    Reline::Unicode.calculate_width(str, allow_escape_code)
  end

  private def key_delete(key)
    if @config.editing_mode_is?(:vi_insert, :emacs)
      ed_delete_next_char(key)
    end
  end

  private def key_newline(key)
    if @is_multiline
      if (@buffer_of_lines.size - 1) == @line_index and @line.bytesize == @byte_pointer
        @add_newline_to_end_of_buffer = true
      end
      next_line = @line.byteslice(@byte_pointer, @line.bytesize - @byte_pointer)
      cursor_line = @line.byteslice(0, @byte_pointer)
      insert_new_line(cursor_line, next_line)
      @cursor = 0
      @check_new_auto_indent = true unless @in_pasting
    end
  end

  # Editline:: +ed-unassigned+ This  editor command always results in an error.
  # GNU Readline:: There is no corresponding macro.
  private def ed_unassigned(key) end # do nothing

  private def process_insert(force: false)
    return if @continuous_insertion_buffer.empty? or (@in_pasting and not force)
    width = Reline::Unicode.calculate_width(@continuous_insertion_buffer)
    bytesize = @continuous_insertion_buffer.bytesize
    if @cursor == @cursor_max
      @line += @continuous_insertion_buffer
    else
      @line = byteinsert(@line, @byte_pointer, @continuous_insertion_buffer)
    end
    @byte_pointer += bytesize
    @cursor += width
    @cursor_max += width
    @continuous_insertion_buffer.clear
  end

  # Editline:: +ed-insert+ (vi input: almost all; emacs: printable characters)
  #            In insert mode, insert the input character left of the cursor
  #            position. In replace mode, overwrite the character at the
  #            cursor and move the cursor to the right by one character
  #            position. Accept an argument to do this repeatedly. It is an
  #            error if the input character is the NUL character (+Ctrl-@+).
  #            Failure to enlarge the edit buffer also results in an error.
  # Editline:: +ed-digit+ (emacs: 0 to 9) If in argument input mode, append
  #            the input digit to the argument being read. Otherwise, call
  #            +ed-insert+. It is an error if the input character is not a
  #            digit or if the existing argument is already greater than a
  #            million.
  # GNU Readline:: +self-insert+ (a, b, A, 1, !, …) Insert yourself.
  private def ed_insert(key)
    str = nil
    width = nil
    bytesize = nil
    if key.instance_of?(String)
      begin
        key.encode(Encoding::UTF_8)
      rescue Encoding::UndefinedConversionError
        return
      end
      str = key
      bytesize = key.bytesize
    else
      begin
        key.chr.encode(Encoding::UTF_8)
      rescue Encoding::UndefinedConversionError
        return
      end
      str = key.chr
      bytesize = 1
    end
    if @in_pasting
      @continuous_insertion_buffer << str
      return
    elsif not @continuous_insertion_buffer.empty?
      process_insert
    end
    width = Reline::Unicode.get_mbchar_width(str)
    if @cursor == @cursor_max
      @line += str
    else
      @line = byteinsert(@line, @byte_pointer, str)
    end
    last_byte_size = Reline::Unicode.get_prev_mbchar_size(@line, @byte_pointer)
    @byte_pointer += bytesize
    last_mbchar = @line.byteslice((@byte_pointer - bytesize - last_byte_size), last_byte_size)
    combined_char = last_mbchar + str
    if last_byte_size != 0 and combined_char.grapheme_clusters.size == 1
      # combined char
      last_mbchar_width = Reline::Unicode.get_mbchar_width(last_mbchar)
      combined_char_width = Reline::Unicode.get_mbchar_width(combined_char)
      if combined_char_width > last_mbchar_width
        width = combined_char_width - last_mbchar_width
      else
        width = 0
      end
    end
    @cursor += width
    @cursor_max += width
  end
  alias_method :ed_digit, :ed_insert
  alias_method :self_insert, :ed_insert

  private def ed_quoted_insert(str, arg: 1)
    @waiting_proc = proc { |key|
      arg.times do
        if key == "\C-j".ord or key == "\C-m".ord
          key_newline(key)
        elsif key == 0
          # Ignore NUL.
        else
          ed_insert(key)
        end
      end
      @waiting_proc = nil
    }
  end
  alias_method :quoted_insert, :ed_quoted_insert

  private def ed_next_char(key, arg: 1)
    byte_size = Reline::Unicode.get_next_mbchar_size(@line, @byte_pointer)
    if (@byte_pointer < @line.bytesize)
      mbchar = @line.byteslice(@byte_pointer, byte_size)
      width = Reline::Unicode.get_mbchar_width(mbchar)
      @cursor += width if width
      @byte_pointer += byte_size
    elsif @is_multiline and @config.editing_mode_is?(:emacs) and @byte_pointer == @line.bytesize and @line_index < @buffer_of_lines.size - 1
      next_line = @buffer_of_lines[@line_index + 1]
      @cursor = 0
      @byte_pointer = 0
      @cursor_max = calculate_width(next_line)
      @previous_line_index = @line_index
      @line_index += 1
    end
    arg -= 1
    ed_next_char(key, arg: arg) if arg > 0
  end
  alias_method :forward_char, :ed_next_char

  private def ed_prev_char(key, arg: 1)
    if @cursor > 0
      byte_size = Reline::Unicode.get_prev_mbchar_size(@line, @byte_pointer)
      @byte_pointer -= byte_size
      mbchar = @line.byteslice(@byte_pointer, byte_size)
      width = Reline::Unicode.get_mbchar_width(mbchar)
      @cursor -= width
    elsif @is_multiline and @config.editing_mode_is?(:emacs) and @byte_pointer == 0 and @line_index > 0
      prev_line = @buffer_of_lines[@line_index - 1]
      @cursor = calculate_width(prev_line)
      @byte_pointer = prev_line.bytesize
      @cursor_max = calculate_width(prev_line)
      @previous_line_index = @line_index
      @line_index -= 1
    end
    arg -= 1
    ed_prev_char(key, arg: arg) if arg > 0
  end
  alias_method :backward_char, :ed_prev_char

  private def vi_first_print(key)
    @byte_pointer, @cursor = Reline::Unicode.vi_first_print(@line)
  end

  private def ed_move_to_beg(key)
    @byte_pointer = @cursor = 0
  end
  alias_method :beginning_of_line, :ed_move_to_beg

  private def ed_move_to_end(key)
    @byte_pointer = 0
    @cursor = 0
    byte_size = 0
    while @byte_pointer < @line.bytesize
      byte_size = Reline::Unicode.get_next_mbchar_size(@line, @byte_pointer)
      if byte_size > 0
        mbchar = @line.byteslice(@byte_pointer, byte_size)
        @cursor += Reline::Unicode.get_mbchar_width(mbchar)
      end
      @byte_pointer += byte_size
    end
  end
  alias_method :end_of_line, :ed_move_to_end

  private def generate_searcher
    Fiber.new do |first_key|
      prev_search_key = first_key
      search_word = String.new(encoding: @encoding)
      multibyte_buf = String.new(encoding: 'ASCII-8BIT')
      last_hit = nil
      case first_key
      when "\C-r".ord
        prompt_name = 'reverse-i-search'
      when "\C-s".ord
        prompt_name = 'i-search'
      end
      loop do
        key = Fiber.yield(search_word)
        search_again = false
        case key
        when -1 # determined
          Reline.last_incremental_search = search_word
          break
        when "\C-h".ord, "\C-?".ord
          grapheme_clusters = search_word.grapheme_clusters
          if grapheme_clusters.size > 0
            grapheme_clusters.pop
            search_word = grapheme_clusters.join
          end
        when "\C-r".ord, "\C-s".ord
          search_again = true if prev_search_key == key
          prev_search_key = key
        else
          multibyte_buf << key
          if multibyte_buf.dup.force_encoding(@encoding).valid_encoding?
            search_word << multibyte_buf.dup.force_encoding(@encoding)
            multibyte_buf.clear
          end
        end
        hit = nil
        if not search_word.empty? and @line_backup_in_history&.include?(search_word)
          @history_pointer = nil
          hit = @line_backup_in_history
        else
          if search_again
            if search_word.empty? and Reline.last_incremental_search
              search_word = Reline.last_incremental_search
            end
            if @history_pointer
              case prev_search_key
              when "\C-r".ord
                history_pointer_base = 0
                history = Reline::HISTORY[0..(@history_pointer - 1)]
              when "\C-s".ord
                history_pointer_base = @history_pointer + 1
                history = Reline::HISTORY[(@history_pointer + 1)..-1]
              end
            else
              history_pointer_base = 0
              history = Reline::HISTORY
            end
          elsif @history_pointer
            case prev_search_key
            when "\C-r".ord
              history_pointer_base = 0
              history = Reline::HISTORY[0..@history_pointer]
            when "\C-s".ord
              history_pointer_base = @history_pointer
              history = Reline::HISTORY[@history_pointer..-1]
            end
          else
            history_pointer_base = 0
            history = Reline::HISTORY
          end
          case prev_search_key
          when "\C-r".ord
            hit_index = history.rindex { |item|
              item.include?(search_word)
            }
          when "\C-s".ord
            hit_index = history.index { |item|
              item.include?(search_word)
            }
          end
          if hit_index
            @history_pointer = history_pointer_base + hit_index
            hit = Reline::HISTORY[@history_pointer]
          end
        end
        case prev_search_key
        when "\C-r".ord
          prompt_name = 'reverse-i-search'
        when "\C-s".ord
          prompt_name = 'i-search'
        end
        if hit
          if @is_multiline
            @buffer_of_lines = hit.split("\n")
            @buffer_of_lines = [String.new(encoding: @encoding)] if @buffer_of_lines.empty?
            @line_index = @buffer_of_lines.size - 1
            @line = @buffer_of_lines.last
            @rerender_all = true
            @searching_prompt = "(%s)`%s'" % [prompt_name, search_word]
          else
            @line = hit
            @searching_prompt = "(%s)`%s': %s" % [prompt_name, search_word, hit]
          end
          last_hit = hit
        else
          if @is_multiline
            @rerender_all = true
            @searching_prompt = "(failed %s)`%s'" % [prompt_name, search_word]
          else
            @searching_prompt = "(failed %s)`%s': %s" % [prompt_name, search_word, last_hit]
          end
        end
      end
    end
  end

  private def incremental_search_history(key)
    unless @history_pointer
      if @is_multiline
        @line_backup_in_history = whole_buffer
      else
        @line_backup_in_history = @line
      end
    end
    searcher = generate_searcher
    searcher.resume(key)
    @searching_prompt = "(reverse-i-search)`': "
    termination_keys = ["\C-j".ord]
    termination_keys.concat(@config.isearch_terminators&.chars&.map(&:ord)) if @config.isearch_terminators
    @waiting_proc = ->(k) {
      case k
      when *termination_keys
        if @history_pointer
          buffer = Reline::HISTORY[@history_pointer]
        else
          buffer = @line_backup_in_history
        end
        if @is_multiline
          @buffer_of_lines = buffer.split("\n")
          @buffer_of_lines = [String.new(encoding: @encoding)] if @buffer_of_lines.empty?
          @line_index = @buffer_of_lines.size - 1
          @line = @buffer_of_lines.last
          @rerender_all = true
        else
          @line = buffer
        end
        @searching_prompt = nil
        @waiting_proc = nil
        @cursor_max = calculate_width(@line)
        @cursor = @byte_pointer = 0
        @rerender_all = true
        @cached_prompt_list = nil
        searcher.resume(-1)
      when "\C-g".ord
        if @is_multiline
          @buffer_of_lines = @line_backup_in_history.split("\n")
          @buffer_of_lines = [String.new(encoding: @encoding)] if @buffer_of_lines.empty?
          @line_index = @buffer_of_lines.size - 1
          @line = @buffer_of_lines.last
          @rerender_all = true
        else
          @line = @line_backup_in_history
        end
        @history_pointer = nil
        @searching_prompt = nil
        @waiting_proc = nil
        @line_backup_in_history = nil
        @cursor_max = calculate_width(@line)
        @cursor = @byte_pointer = 0
        @rerender_all = true
      else
        chr = k.is_a?(String) ? k : k.chr(Encoding::ASCII_8BIT)
        if chr.match?(/[[:print:]]/) or k == "\C-h".ord or k == "\C-?".ord or k == "\C-r".ord or k == "\C-s".ord
          searcher.resume(k)
        else
          if @history_pointer
            line = Reline::HISTORY[@history_pointer]
          else
            line = @line_backup_in_history
          end
          if @is_multiline
            @line_backup_in_history = whole_buffer
            @buffer_of_lines = line.split("\n")
            @buffer_of_lines = [String.new(encoding: @encoding)] if @buffer_of_lines.empty?
            @line_index = @buffer_of_lines.size - 1
            @line = @buffer_of_lines.last
            @rerender_all = true
          else
            @line_backup_in_history = @line
            @line = line
          end
          @searching_prompt = nil
          @waiting_proc = nil
          @cursor_max = calculate_width(@line)
          @cursor = @byte_pointer = 0
          @rerender_all = true
          @cached_prompt_list = nil
          searcher.resume(-1)
        end
      end
    }
  end

  private def vi_search_prev(key)
    incremental_search_history(key)
  end
  alias_method :reverse_search_history, :vi_search_prev

  private def vi_search_next(key)
    incremental_search_history(key)
  end
  alias_method :forward_search_history, :vi_search_next

  private def ed_search_prev_history(key, arg: 1)
    history = nil
    h_pointer = nil
    line_no = nil
    substr = @line.slice(0, @byte_pointer)
    if @history_pointer.nil?
      return if not @line.empty? and substr.empty?
      history = Reline::HISTORY
    elsif @history_pointer.zero?
      history = nil
      h_pointer = nil
    else
      history = Reline::HISTORY.slice(0, @history_pointer)
    end
    return if history.nil?
    if @is_multiline
      h_pointer = history.rindex { |h|
        h.split("\n").each_with_index { |l, i|
          if l.start_with?(substr)
            line_no = i
            break
          end
        }
        not line_no.nil?
      }
    else
      h_pointer = history.rindex { |l|
        l.start_with?(substr)
      }
    end
    return if h_pointer.nil?
    @history_pointer = h_pointer
    if @is_multiline
      @buffer_of_lines = Reline::HISTORY[@history_pointer].split("\n")
      @buffer_of_lines = [String.new(encoding: @encoding)] if @buffer_of_lines.empty?
      @line_index = line_no
      @line = @buffer_of_lines[@line_index]
      @rerender_all = true
    else
      @line = Reline::HISTORY[@history_pointer]
    end
    @cursor_max = calculate_width(@line)
    arg -= 1
    ed_search_prev_history(key, arg: arg) if arg > 0
  end
  alias_method :history_search_backward, :ed_search_prev_history

  private def ed_search_next_history(key, arg: 1)
    substr = @line.slice(0, @byte_pointer)
    if @history_pointer.nil?
      return
    elsif @history_pointer == (Reline::HISTORY.size - 1) and not substr.empty?
      return
    end
    history = Reline::HISTORY.slice((@history_pointer + 1)..-1)
    h_pointer = nil
    line_no = nil
    if @is_multiline
      h_pointer = history.index { |h|
        h.split("\n").each_with_index { |l, i|
          if l.start_with?(substr)
            line_no = i
            break
          end
        }
        not line_no.nil?
      }
    else
      h_pointer = history.index { |l|
        l.start_with?(substr)
      }
    end
    h_pointer += @history_pointer + 1 if h_pointer and @history_pointer
    return if h_pointer.nil? and not substr.empty?
    @history_pointer = h_pointer
    if @is_multiline
      if @history_pointer.nil? and substr.empty?
        @buffer_of_lines = []
        @line_index = 0
      else
        @buffer_of_lines = Reline::HISTORY[@history_pointer].split("\n")
        @line_index = line_no
      end
      @buffer_of_lines = [String.new(encoding: @encoding)] if @buffer_of_lines.empty?
      @line = @buffer_of_lines[@line_index]
      @rerender_all = true
    else
      if @history_pointer.nil? and substr.empty?
        @line = ''
      else
        @line = Reline::HISTORY[@history_pointer]
      end
    end
    @cursor_max = calculate_width(@line)
    arg -= 1
    ed_search_next_history(key, arg: arg) if arg > 0
  end
  alias_method :history_search_forward, :ed_search_next_history

  private def ed_prev_history(key, arg: 1)
    if @is_multiline and @line_index > 0
      @previous_line_index = @line_index
      @line_index -= 1
      return
    end
    if Reline::HISTORY.empty?
      return
    end
    if @history_pointer.nil?
      @history_pointer = Reline::HISTORY.size - 1
      if @is_multiline
        @line_backup_in_history = whole_buffer
        @buffer_of_lines = Reline::HISTORY[@history_pointer].split("\n")
        @buffer_of_lines = [String.new(encoding: @encoding)] if @buffer_of_lines.empty?
        @line_index = @buffer_of_lines.size - 1
        @line = @buffer_of_lines.last
        @rerender_all = true
      else
        @line_backup_in_history = @line
        @line = Reline::HISTORY[@history_pointer]
      end
    elsif @history_pointer.zero?
      return
    else
      if @is_multiline
        Reline::HISTORY[@history_pointer] = whole_buffer
        @history_pointer -= 1
        @buffer_of_lines = Reline::HISTORY[@history_pointer].split("\n")
        @buffer_of_lines = [String.new(encoding: @encoding)] if @buffer_of_lines.empty?
        @line_index = @buffer_of_lines.size - 1
        @line = @buffer_of_lines.last
        @rerender_all = true
      else
        Reline::HISTORY[@history_pointer] = @line
        @history_pointer -= 1
        @line = Reline::HISTORY[@history_pointer]
      end
    end
    if @config.editing_mode_is?(:emacs, :vi_insert)
      @cursor_max = @cursor = calculate_width(@line)
      @byte_pointer = @line.bytesize
    elsif @config.editing_mode_is?(:vi_command)
      @byte_pointer = @cursor = 0
      @cursor_max = calculate_width(@line)
    end
    arg -= 1
    ed_prev_history(key, arg: arg) if arg > 0
  end
  alias_method :previous_history, :ed_prev_history

  private def ed_next_history(key, arg: 1)
    if @is_multiline and @line_index < (@buffer_of_lines.size - 1)
      @previous_line_index = @line_index
      @line_index += 1
      return
    end
    if @history_pointer.nil?
      return
    elsif @history_pointer == (Reline::HISTORY.size - 1)
      if @is_multiline
        @history_pointer = nil
        @buffer_of_lines = @line_backup_in_history.split("\n")
        @buffer_of_lines = [String.new(encoding: @encoding)] if @buffer_of_lines.empty?
        @line_index = 0
        @line = @buffer_of_lines.first
        @rerender_all = true
      else
        @history_pointer = nil
        @line = @line_backup_in_history
      end
    else
      if @is_multiline
        Reline::HISTORY[@history_pointer] = whole_buffer
        @history_pointer += 1
        @buffer_of_lines = Reline::HISTORY[@history_pointer].split("\n")
        @buffer_of_lines = [String.new(encoding: @encoding)] if @buffer_of_lines.empty?
        @line_index = 0
        @line = @buffer_of_lines.first
        @rerender_all = true
      else
        Reline::HISTORY[@history_pointer] = @line
        @history_pointer += 1
        @line = Reline::HISTORY[@history_pointer]
      end
    end
    @line = '' unless @line
    if @config.editing_mode_is?(:emacs, :vi_insert)
      @cursor_max = @cursor = calculate_width(@line)
      @byte_pointer = @line.bytesize
    elsif @config.editing_mode_is?(:vi_command)
      @byte_pointer = @cursor = 0
      @cursor_max = calculate_width(@line)
    end
    arg -= 1
    ed_next_history(key, arg: arg) if arg > 0
  end
  alias_method :next_history, :ed_next_history

  private def ed_newline(key)
    process_insert(force: true)
    if @is_multiline
      if @config.editing_mode_is?(:vi_command)
        if @line_index < (@buffer_of_lines.size - 1)
          ed_next_history(key) # means cursor down
        else
          # should check confirm_multiline_termination to finish?
          finish
        end
      else
        if @line_index == (@buffer_of_lines.size - 1)
          if confirm_multiline_termination
            finish
          else
            key_newline(key)
          end
        else
          # should check confirm_multiline_termination to finish?
          @previous_line_index = @line_index
          @line_index = @buffer_of_lines.size - 1
          finish
        end
      end
    else
      if @history_pointer
        Reline::HISTORY[@history_pointer] = @line
        @history_pointer = nil
      end
      finish
    end
  end

  private def em_delete_prev_char(key, arg: 1)
    if @is_multiline and @cursor == 0 and @line_index > 0
      @buffer_of_lines[@line_index] = @line
      @cursor = calculate_width(@buffer_of_lines[@line_index - 1])
      @byte_pointer = @buffer_of_lines[@line_index - 1].bytesize
      @buffer_of_lines[@line_index - 1] += @buffer_of_lines.delete_at(@line_index)
      @line_index -= 1
      @line = @buffer_of_lines[@line_index]
      @cursor_max = calculate_width(@line)
      @rerender_all = true
    elsif @cursor > 0
      byte_size = Reline::Unicode.get_prev_mbchar_size(@line, @byte_pointer)
      @byte_pointer -= byte_size
      @line, mbchar = byteslice!(@line, @byte_pointer, byte_size)
      width = Reline::Unicode.get_mbchar_width(mbchar)
      @cursor -= width
      @cursor_max -= width
    end
    arg -= 1
    em_delete_prev_char(key, arg: arg) if arg > 0
  end
  alias_method :backward_delete_char, :em_delete_prev_char

  # Editline:: +ed-kill-line+ (vi command: +D+, +Ctrl-K+; emacs: +Ctrl-K+,
  #            +Ctrl-U+) + Kill from the cursor to the end of the line.
  # GNU Readline:: +kill-line+ (+C-k+) Kill the text from point to the end of
  #                the line. With a negative numeric argument, kill backward
  #                from the cursor to the beginning of the current line.
  private def ed_kill_line(key)
    if @line.bytesize > @byte_pointer
      @line, deleted = byteslice!(@line, @byte_pointer, @line.bytesize - @byte_pointer)
      @byte_pointer = @line.bytesize
      @cursor = @cursor_max = calculate_width(@line)
      @kill_ring.append(deleted)
    elsif @is_multiline and @byte_pointer == @line.bytesize and @buffer_of_lines.size > @line_index + 1
      @cursor = calculate_width(@line)
      @byte_pointer = @line.bytesize
      @line += @buffer_of_lines.delete_at(@line_index + 1)
      @cursor_max = calculate_width(@line)
      @buffer_of_lines[@line_index] = @line
      @rerender_all = true
      @rest_height += 1
    end
  end
  alias_method :kill_line, :ed_kill_line

  # Editline:: +vi-kill-line-prev+ (vi: +Ctrl-U+) Delete the string from the
  #            beginning  of the edit buffer to the cursor and save it to the
  #            cut buffer.
  # GNU Readline:: +unix-line-discard+ (+C-u+) Kill backward from the cursor
  #                to the beginning of the current line.
  private def vi_kill_line_prev(key)
    if @byte_pointer > 0
      @line, deleted = byteslice!(@line, 0, @byte_pointer)
      @byte_pointer = 0
      @kill_ring.append(deleted, true)
      @cursor_max = calculate_width(@line)
      @cursor = 0
    end
  end
  alias_method :unix_line_discard, :vi_kill_line_prev

  # Editline:: +em-kill-line+ (not bound) Delete the entire contents of the
  #            edit buffer and save it to the cut buffer. +vi-kill-line-prev+
  # GNU Readline:: +kill-whole-line+ (not bound) Kill all characters on the
  #                current line, no matter where point is.
  private def em_kill_line(key)
    if @line.size > 0
      @kill_ring.append(@line.dup, true)
      @line.clear
      @byte_pointer = 0
      @cursor_max = 0
      @cursor = 0
    end
  end
  alias_method :kill_whole_line, :em_kill_line

  private def em_delete(key)
    if (not @is_multiline and @line.empty?) or (@is_multiline and @line.empty? and @buffer_of_lines.size == 1)
      @line = nil
      if @buffer_of_lines.size > 1
        scroll_down(@highest_in_all - @first_line_started_from)
      end
      Reline::IOGate.move_cursor_column(0)
      @eof = true
      finish
    elsif @byte_pointer < @line.bytesize
      splitted_last = @line.byteslice(@byte_pointer, @line.bytesize)
      mbchar = splitted_last.grapheme_clusters.first
      width = Reline::Unicode.get_mbchar_width(mbchar)
      @cursor_max -= width
      @line, = byteslice!(@line, @byte_pointer, mbchar.bytesize)
    elsif @is_multiline and @byte_pointer == @line.bytesize and @buffer_of_lines.size > @line_index + 1
      @cursor = calculate_width(@line)
      @byte_pointer = @line.bytesize
      @line += @buffer_of_lines.delete_at(@line_index + 1)
      @cursor_max = calculate_width(@line)
      @buffer_of_lines[@line_index] = @line
      @rerender_all = true
      @rest_height += 1
    end
  end
  alias_method :delete_char, :em_delete

  private def em_delete_or_list(key)
    if @line.empty? or @byte_pointer < @line.bytesize
      em_delete(key)
    else # show completed list
      result = call_completion_proc
      if result.is_a?(Array)
        complete(result, true)
      end
    end
  end
  alias_method :delete_char_or_list, :em_delete_or_list

  private def em_yank(key)
    yanked = @kill_ring.yank
    if yanked
      @line = byteinsert(@line, @byte_pointer, yanked)
      yanked_width = calculate_width(yanked)
      @cursor += yanked_width
      @cursor_max += yanked_width
      @byte_pointer += yanked.bytesize
    end
  end
  alias_method :yank, :em_yank

  private def em_yank_pop(key)
    yanked, prev_yank = @kill_ring.yank_pop
    if yanked
      prev_yank_width = calculate_width(prev_yank)
      @cursor -= prev_yank_width
      @cursor_max -= prev_yank_width
      @byte_pointer -= prev_yank.bytesize
      @line, = byteslice!(@line, @byte_pointer, prev_yank.bytesize)
      @line = byteinsert(@line, @byte_pointer, yanked)
      yanked_width = calculate_width(yanked)
      @cursor += yanked_width
      @cursor_max += yanked_width
      @byte_pointer += yanked.bytesize
    end
  end
  alias_method :yank_pop, :em_yank_pop

  private def ed_clear_screen(key)
    @cleared = true
  end
  alias_method :clear_screen, :ed_clear_screen

  private def em_next_word(key)
    if @line.bytesize > @byte_pointer
      byte_size, width = Reline::Unicode.em_forward_word(@line, @byte_pointer)
      @byte_pointer += byte_size
      @cursor += width
    end
  end
  alias_method :forward_word, :em_next_word

  private def ed_prev_word(key)
    if @byte_pointer > 0
      byte_size, width = Reline::Unicode.em_backward_word(@line, @byte_pointer)
      @byte_pointer -= byte_size
      @cursor -= width
    end
  end
  alias_method :backward_word, :ed_prev_word

  private def em_delete_next_word(key)
    if @line.bytesize > @byte_pointer
      byte_size, width = Reline::Unicode.em_forward_word(@line, @byte_pointer)
      @line, word = byteslice!(@line, @byte_pointer, byte_size)
      @kill_ring.append(word)
      @cursor_max -= width
    end
  end

  private def ed_delete_prev_word(key)
    if @byte_pointer > 0
      byte_size, width = Reline::Unicode.em_backward_word(@line, @byte_pointer)
      @line, word = byteslice!(@line, @byte_pointer - byte_size, byte_size)
      @kill_ring.append(word, true)
      @byte_pointer -= byte_size
      @cursor -= width
      @cursor_max -= width
    end
  end

  private def ed_transpose_chars(key)
    if @byte_pointer > 0
      if @cursor_max > @cursor
        byte_size = Reline::Unicode.get_next_mbchar_size(@line, @byte_pointer)
        mbchar = @line.byteslice(@byte_pointer, byte_size)
        width = Reline::Unicode.get_mbchar_width(mbchar)
        @cursor += width
        @byte_pointer += byte_size
      end
      back1_byte_size = Reline::Unicode.get_prev_mbchar_size(@line, @byte_pointer)
      if (@byte_pointer - back1_byte_size) > 0
        back2_byte_size = Reline::Unicode.get_prev_mbchar_size(@line, @byte_pointer - back1_byte_size)
        back2_pointer = @byte_pointer - back1_byte_size - back2_byte_size
        @line, back2_mbchar = byteslice!(@line, back2_pointer, back2_byte_size)
        @line = byteinsert(@line, @byte_pointer - back2_byte_size, back2_mbchar)
      end
    end
  end
  alias_method :transpose_chars, :ed_transpose_chars

  private def ed_transpose_words(key)
    left_word_start, middle_start, right_word_start, after_start = Reline::Unicode.ed_transpose_words(@line, @byte_pointer)
    before = @line.byteslice(0, left_word_start)
    left_word = @line.byteslice(left_word_start, middle_start - left_word_start)
    middle = @line.byteslice(middle_start, right_word_start - middle_start)
    right_word = @line.byteslice(right_word_start, after_start - right_word_start)
    after = @line.byteslice(after_start, @line.bytesize - after_start)
    return if left_word.empty? or right_word.empty?
    @line = before + right_word + middle + left_word + after
    from_head_to_left_word = before + right_word + middle + left_word
    @byte_pointer = from_head_to_left_word.bytesize
    @cursor = calculate_width(from_head_to_left_word)
  end
  alias_method :transpose_words, :ed_transpose_words

  private def em_capitol_case(key)
    if @line.bytesize > @byte_pointer
      byte_size, _, new_str = Reline::Unicode.em_forward_word_with_capitalization(@line, @byte_pointer)
      before = @line.byteslice(0, @byte_pointer)
      after = @line.byteslice((@byte_pointer + byte_size)..-1)
      @line = before + new_str + after
      @byte_pointer += new_str.bytesize
      @cursor += calculate_width(new_str)
    end
  end
  alias_method :capitalize_word, :em_capitol_case

  private def em_lower_case(key)
    if @line.bytesize > @byte_pointer
      byte_size, = Reline::Unicode.em_forward_word(@line, @byte_pointer)
      part = @line.byteslice(@byte_pointer, byte_size).grapheme_clusters.map { |mbchar|
        mbchar =~ /[A-Z]/ ? mbchar.downcase : mbchar
      }.join
      rest = @line.byteslice((@byte_pointer + byte_size)..-1)
      @line = @line.byteslice(0, @byte_pointer) + part
      @byte_pointer = @line.bytesize
      @cursor = calculate_width(@line)
      @cursor_max = @cursor + calculate_width(rest)
      @line += rest
    end
  end
  alias_method :downcase_word, :em_lower_case

  private def em_upper_case(key)
    if @line.bytesize > @byte_pointer
      byte_size, = Reline::Unicode.em_forward_word(@line, @byte_pointer)
      part = @line.byteslice(@byte_pointer, byte_size).grapheme_clusters.map { |mbchar|
        mbchar =~ /[a-z]/ ? mbchar.upcase : mbchar
      }.join
      rest = @line.byteslice((@byte_pointer + byte_size)..-1)
      @line = @line.byteslice(0, @byte_pointer) + part
      @byte_pointer = @line.bytesize
      @cursor = calculate_width(@line)
      @cursor_max = @cursor + calculate_width(rest)
      @line += rest
    end
  end
  alias_method :upcase_word, :em_upper_case

  private def em_kill_region(key)
    if @byte_pointer > 0
      byte_size, width = Reline::Unicode.em_big_backward_word(@line, @byte_pointer)
      @line, deleted = byteslice!(@line, @byte_pointer - byte_size, byte_size)
      @byte_pointer -= byte_size
      @cursor -= width
      @cursor_max -= width
      @kill_ring.append(deleted, true)
    end
  end
  alias_method :unix_word_rubout, :em_kill_region

  private def copy_for_vi(text)
    if @config.editing_mode_is?(:vi_insert) or @config.editing_mode_is?(:vi_command)
      @vi_clipboard = text
    end
  end

  private def vi_insert(key)
    @config.editing_mode = :vi_insert
  end

  private def vi_add(key)
    @config.editing_mode = :vi_insert
    ed_next_char(key)
  end

  private def vi_command_mode(key)
    ed_prev_char(key)
    @config.editing_mode = :vi_command
  end
  alias_method :vi_movement_mode, :vi_command_mode

  private def vi_next_word(key, arg: 1)
    if @line.bytesize > @byte_pointer
      byte_size, width = Reline::Unicode.vi_forward_word(@line, @byte_pointer, @drop_terminate_spaces)
      @byte_pointer += byte_size
      @cursor += width
    end
    arg -= 1
    vi_next_word(key, arg: arg) if arg > 0
  end

  private def vi_prev_word(key, arg: 1)
    if @byte_pointer > 0
      byte_size, width = Reline::Unicode.vi_backward_word(@line, @byte_pointer)
      @byte_pointer -= byte_size
      @cursor -= width
    end
    arg -= 1
    vi_prev_word(key, arg: arg) if arg > 0
  end

  private def vi_end_word(key, arg: 1, inclusive: false)
    if @line.bytesize > @byte_pointer
      byte_size, width = Reline::Unicode.vi_forward_end_word(@line, @byte_pointer)
      @byte_pointer += byte_size
      @cursor += width
    end
    arg -= 1
    if inclusive and arg.zero?
      byte_size = Reline::Unicode.get_next_mbchar_size(@line, @byte_pointer)
      if byte_size > 0
        c = @line.byteslice(@byte_pointer, byte_size)
        width = Reline::Unicode.get_mbchar_width(c)
        @byte_pointer += byte_size
        @cursor += width
      end
    end
    vi_end_word(key, arg: arg) if arg > 0
  end

  private def vi_next_big_word(key, arg: 1)
    if @line.bytesize > @byte_pointer
      byte_size, width = Reline::Unicode.vi_big_forward_word(@line, @byte_pointer)
      @byte_pointer += byte_size
      @cursor += width
    end
    arg -= 1
    vi_next_big_word(key, arg: arg) if arg > 0
  end

  private def vi_prev_big_word(key, arg: 1)
    if @byte_pointer > 0
      byte_size, width = Reline::Unicode.vi_big_backward_word(@line, @byte_pointer)
      @byte_pointer -= byte_size
      @cursor -= width
    end
    arg -= 1
    vi_prev_big_word(key, arg: arg) if arg > 0
  end

  private def vi_end_big_word(key, arg: 1, inclusive: false)
    if @line.bytesize > @byte_pointer
      byte_size, width = Reline::Unicode.vi_big_forward_end_word(@line, @byte_pointer)
      @byte_pointer += byte_size
      @cursor += width
    end
    arg -= 1
    if inclusive and arg.zero?
      byte_size = Reline::Unicode.get_next_mbchar_size(@line, @byte_pointer)
      if byte_size > 0
        c = @line.byteslice(@byte_pointer, byte_size)
        width = Reline::Unicode.get_mbchar_width(c)
        @byte_pointer += byte_size
        @cursor += width
      end
    end
    vi_end_big_word(key, arg: arg) if arg > 0
  end

  private def vi_delete_prev_char(key)
    if @is_multiline and @cursor == 0 and @line_index > 0
      @buffer_of_lines[@line_index] = @line
      @cursor = calculate_width(@buffer_of_lines[@line_index - 1])
      @byte_pointer = @buffer_of_lines[@line_index - 1].bytesize
      @buffer_of_lines[@line_index - 1] += @buffer_of_lines.delete_at(@line_index)
      @line_index -= 1
      @line = @buffer_of_lines[@line_index]
      @cursor_max = calculate_width(@line)
      @rerender_all = true
    elsif @cursor > 0
      byte_size = Reline::Unicode.get_prev_mbchar_size(@line, @byte_pointer)
      @byte_pointer -= byte_size
      @line, mbchar = byteslice!(@line, @byte_pointer, byte_size)
      width = Reline::Unicode.get_mbchar_width(mbchar)
      @cursor -= width
      @cursor_max -= width
    end
  end

  private def vi_insert_at_bol(key)
    ed_move_to_beg(key)
    @config.editing_mode = :vi_insert
  end

  private def vi_add_at_eol(key)
    ed_move_to_end(key)
    @config.editing_mode = :vi_insert
  end

  private def ed_delete_prev_char(key, arg: 1)
    deleted = ''
    arg.times do
      if @cursor > 0
        byte_size = Reline::Unicode.get_prev_mbchar_size(@line, @byte_pointer)
        @byte_pointer -= byte_size
        @line, mbchar = byteslice!(@line, @byte_pointer, byte_size)
        deleted.prepend(mbchar)
        width = Reline::Unicode.get_mbchar_width(mbchar)
        @cursor -= width
        @cursor_max -= width
      end
    end
    copy_for_vi(deleted)
  end

  private def vi_zero(key)
    @byte_pointer = 0
    @cursor = 0
  end

  private def vi_change_meta(key, arg: 1)
    @drop_terminate_spaces = true
    @waiting_operator_proc = proc { |cursor_diff, byte_pointer_diff|
      if byte_pointer_diff > 0
        @line, cut = byteslice!(@line, @byte_pointer, byte_pointer_diff)
      elsif byte_pointer_diff < 0
        @line, cut = byteslice!(@line, @byte_pointer + byte_pointer_diff, -byte_pointer_diff)
      end
      copy_for_vi(cut)
      @cursor += cursor_diff if cursor_diff < 0
      @cursor_max -= cursor_diff.abs
      @byte_pointer += byte_pointer_diff if byte_pointer_diff < 0
      @config.editing_mode = :vi_insert
      @drop_terminate_spaces = false
    }
    @waiting_operator_vi_arg = arg
  end

  private def vi_delete_meta(key, arg: 1)
    @waiting_operator_proc = proc { |cursor_diff, byte_pointer_diff|
      if byte_pointer_diff > 0
        @line, cut = byteslice!(@line, @byte_pointer, byte_pointer_diff)
      elsif byte_pointer_diff < 0
        @line, cut = byteslice!(@line, @byte_pointer + byte_pointer_diff, -byte_pointer_diff)
      end
      copy_for_vi(cut)
      @cursor += cursor_diff if cursor_diff < 0
      @cursor_max -= cursor_diff.abs
      @byte_pointer += byte_pointer_diff if byte_pointer_diff < 0
    }
    @waiting_operator_vi_arg = arg
  end

  private def vi_yank(key, arg: 1)
    @waiting_operator_proc = proc { |cursor_diff, byte_pointer_diff|
      if byte_pointer_diff > 0
        cut = @line.byteslice(@byte_pointer, byte_pointer_diff)
      elsif byte_pointer_diff < 0
        cut = @line.byteslice(@byte_pointer + byte_pointer_diff, -byte_pointer_diff)
      end
      copy_for_vi(cut)
    }
    @waiting_operator_vi_arg = arg
  end

  private def vi_list_or_eof(key)
    if (not @is_multiline and @line.empty?) or (@is_multiline and @line.empty? and @buffer_of_lines.size == 1)
      @line = nil
      if @buffer_of_lines.size > 1
        scroll_down(@highest_in_all - @first_line_started_from)
      end
      Reline::IOGate.move_cursor_column(0)
      @eof = true
      finish
    else
      ed_newline(key)
    end
  end
  alias_method :vi_end_of_transmission, :vi_list_or_eof
  alias_method :vi_eof_maybe, :vi_list_or_eof

  private def ed_delete_next_char(key, arg: 1)
    byte_size = Reline::Unicode.get_next_mbchar_size(@line, @byte_pointer)
    unless @line.empty? || byte_size == 0
      @line, mbchar = byteslice!(@line, @byte_pointer, byte_size)
      copy_for_vi(mbchar)
      width = Reline::Unicode.get_mbchar_width(mbchar)
      @cursor_max -= width
      if @cursor > 0 and @cursor >= @cursor_max
        byte_size = Reline::Unicode.get_prev_mbchar_size(@line, @byte_pointer)
        mbchar = @line.byteslice(@byte_pointer - byte_size, byte_size)
        width = Reline::Unicode.get_mbchar_width(mbchar)
        @byte_pointer -= byte_size
        @cursor -= width
      end
    end
    arg -= 1
    ed_delete_next_char(key, arg: arg) if arg > 0
  end

  private def vi_to_history_line(key)
    if Reline::HISTORY.empty?
      return
    end
    if @history_pointer.nil?
      @history_pointer = 0
      @line_backup_in_history = @line
      @line = Reline::HISTORY[@history_pointer]
      @cursor_max = calculate_width(@line)
      @cursor = 0
      @byte_pointer = 0
    elsif @history_pointer.zero?
      return
    else
      Reline::HISTORY[@history_pointer] = @line
      @history_pointer = 0
      @line = Reline::HISTORY[@history_pointer]
      @cursor_max = calculate_width(@line)
      @cursor = 0
      @byte_pointer = 0
    end
  end

  private def vi_histedit(key)
    path = Tempfile.open { |fp|
      if @is_multiline
        fp.write whole_lines.join("\n")
      else
        fp.write @line
      end
      fp.path
    }
    system("#{ENV['EDITOR']} #{path}")
    if @is_multiline
      @buffer_of_lines = File.read(path).split("\n")
      @buffer_of_lines = [String.new(encoding: @encoding)] if @buffer_of_lines.empty?
      @line_index = 0
      @line = @buffer_of_lines[@line_index]
      @rerender_all = true
    else
      @line = File.read(path)
    end
    finish
  end

  private def vi_paste_prev(key, arg: 1)
    if @vi_clipboard.size > 0
      @line = byteinsert(@line, @byte_pointer, @vi_clipboard)
      @cursor_max += calculate_width(@vi_clipboard)
      cursor_point = @vi_clipboard.grapheme_clusters[0..-2].join
      @cursor += calculate_width(cursor_point)
      @byte_pointer += cursor_point.bytesize
    end
    arg -= 1
    vi_paste_prev(key, arg: arg) if arg > 0
  end

  private def vi_paste_next(key, arg: 1)
    if @vi_clipboard.size > 0
      byte_size = Reline::Unicode.get_next_mbchar_size(@line, @byte_pointer)
      @line = byteinsert(@line, @byte_pointer + byte_size, @vi_clipboard)
      @cursor_max += calculate_width(@vi_clipboard)
      @cursor += calculate_width(@vi_clipboard)
      @byte_pointer += @vi_clipboard.bytesize
    end
    arg -= 1
    vi_paste_next(key, arg: arg) if arg > 0
  end

  private def ed_argument_digit(key)
    if @vi_arg.nil?
      if key.chr.to_i.zero?
        if key.anybits?(0b10000000)
          unescaped_key = key ^ 0b10000000
          unless unescaped_key.chr.to_i.zero?
            @vi_arg = unescaped_key.chr.to_i
          end
        end
      else
        @vi_arg = key.chr.to_i
      end
    else
      @vi_arg = @vi_arg * 10 + key.chr.to_i
    end
  end

  private def vi_to_column(key, arg: 0)
    @byte_pointer, @cursor = @line.grapheme_clusters.inject([0, 0]) { |total, gc|
      # total has [byte_size, cursor]
      mbchar_width = Reline::Unicode.get_mbchar_width(gc)
      if (total.last + mbchar_width) >= arg
        break total
      elsif (total.last + mbchar_width) >= @cursor_max
        break total
      else
        total = [total.first + gc.bytesize, total.last + mbchar_width]
        total
      end
    }
  end

  private def vi_replace_char(key, arg: 1)
    @waiting_proc = ->(k) {
      if arg == 1
        byte_size = Reline::Unicode.get_next_mbchar_size(@line, @byte_pointer)
        before = @line.byteslice(0, @byte_pointer)
        remaining_point = @byte_pointer + byte_size
        after = @line.byteslice(remaining_point, @line.bytesize - remaining_point)
        @line = before + k.chr + after
        @cursor_max = calculate_width(@line)
        @waiting_proc = nil
      elsif arg > 1
        byte_size = 0
        arg.times do
          byte_size += Reline::Unicode.get_next_mbchar_size(@line, @byte_pointer + byte_size)
        end
        before = @line.byteslice(0, @byte_pointer)
        remaining_point = @byte_pointer + byte_size
        after = @line.byteslice(remaining_point, @line.bytesize - remaining_point)
        replaced = k.chr * arg
        @line = before + replaced + after
        @byte_pointer += replaced.bytesize
        @cursor += calculate_width(replaced)
        @cursor_max = calculate_width(@line)
        @waiting_proc = nil
      end
    }
  end

  private def vi_next_char(key, arg: 1, inclusive: false)
    @waiting_proc = ->(key_for_proc) { search_next_char(key_for_proc, arg, inclusive: inclusive) }
  end

  private def vi_to_next_char(key, arg: 1, inclusive: false)
    @waiting_proc = ->(key_for_proc) { search_next_char(key_for_proc, arg, need_prev_char: true, inclusive: inclusive) }
  end

  private def search_next_char(key, arg, need_prev_char: false, inclusive: false)
    if key.instance_of?(String)
      inputed_char = key
    else
      inputed_char = key.chr
    end
    prev_total = nil
    total = nil
    found = false
    @line.byteslice(@byte_pointer..-1).grapheme_clusters.each do |mbchar|
      # total has [byte_size, cursor]
      unless total
        # skip cursor point
        width = Reline::Unicode.get_mbchar_width(mbchar)
        total = [mbchar.bytesize, width]
      else
        if inputed_char == mbchar
          arg -= 1
          if arg.zero?
            found = true
            break
          end
        end
        width = Reline::Unicode.get_mbchar_width(mbchar)
        prev_total = total
        total = [total.first + mbchar.bytesize, total.last + width]
      end
    end
    if not need_prev_char and found and total
      byte_size, width = total
      @byte_pointer += byte_size
      @cursor += width
    elsif need_prev_char and found and prev_total
      byte_size, width = prev_total
      @byte_pointer += byte_size
      @cursor += width
    end
    if inclusive
      byte_size = Reline::Unicode.get_next_mbchar_size(@line, @byte_pointer)
      if byte_size > 0
        c = @line.byteslice(@byte_pointer, byte_size)
        width = Reline::Unicode.get_mbchar_width(c)
        @byte_pointer += byte_size
        @cursor += width
      end
    end
    @waiting_proc = nil
  end

  private def vi_prev_char(key, arg: 1)
    @waiting_proc = ->(key_for_proc) { search_prev_char(key_for_proc, arg) }
  end

  private def vi_to_prev_char(key, arg: 1)
    @waiting_proc = ->(key_for_proc) { search_prev_char(key_for_proc, arg, true) }
  end

  private def search_prev_char(key, arg, need_next_char = false)
    if key.instance_of?(String)
      inputed_char = key
    else
      inputed_char = key.chr
    end
    prev_total = nil
    total = nil
    found = false
    @line.byteslice(0..@byte_pointer).grapheme_clusters.reverse_each do |mbchar|
      # total has [byte_size, cursor]
      unless total
        # skip cursor point
        width = Reline::Unicode.get_mbchar_width(mbchar)
        total = [mbchar.bytesize, width]
      else
        if inputed_char == mbchar
          arg -= 1
          if arg.zero?
            found = true
            break
          end
        end
        width = Reline::Unicode.get_mbchar_width(mbchar)
        prev_total = total
        total = [total.first + mbchar.bytesize, total.last + width]
      end
    end
    if not need_next_char and found and total
      byte_size, width = total
      @byte_pointer -= byte_size
      @cursor -= width
    elsif need_next_char and found and prev_total
      byte_size, width = prev_total
      @byte_pointer -= byte_size
      @cursor -= width
    end
    @waiting_proc = nil
  end

  private def vi_join_lines(key, arg: 1)
    if @is_multiline and @buffer_of_lines.size > @line_index + 1
      @cursor = calculate_width(@line)
      @byte_pointer = @line.bytesize
      @line += ' ' + @buffer_of_lines.delete_at(@line_index + 1).lstrip
      @cursor_max = calculate_width(@line)
      @buffer_of_lines[@line_index] = @line
      @rerender_all = true
      @rest_height += 1
    end
    arg -= 1
    vi_join_lines(key, arg: arg) if arg > 0
  end

  private def em_set_mark(key)
    @mark_pointer = [@byte_pointer, @line_index]
  end
  alias_method :set_mark, :em_set_mark

  private def em_exchange_mark(key)
    return unless @mark_pointer
    new_pointer = [@byte_pointer, @line_index]
    @previous_line_index = @line_index
    @byte_pointer, @line_index = @mark_pointer
    @cursor = calculate_width(@line.byteslice(0, @byte_pointer))
    @cursor_max = calculate_width(@line)
    @mark_pointer = new_pointer
  end
  alias_method :exchange_point_and_mark, :em_exchange_mark
end
