require 'reline/kill_ring'
require 'reline/unicode'

require 'tempfile'

class Reline::LineEditor
  # TODO: Use "private alias_method" idiom after drop Ruby 2.5.
  attr_reader :byte_pointer
  attr_accessor :confirm_multiline_termination_proc
  attr_accessor :completion_proc
  attr_accessor :completion_append_character
  attr_accessor :output_modifier_proc
  attr_accessor :prompt_proc
  attr_accessor :auto_indent_proc
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
  }

  module CompletionState
    NORMAL = :normal
    COMPLETION = :completion
    MENU = :menu
    MENU_WITH_PERFECT_MATCH = :menu_with_perfect_match
    PERFECT_MATCH = :perfect_match
  end

  RenderedScreen = Struct.new(:base_y, :lines, :cursor_y, keyword_init: true)

  CompletionJourneyState = Struct.new(:line_index, :pre, :target, :post, :list, :pointer)
  NullActionState = [nil, nil].freeze

  class MenuInfo
    attr_reader :list

    def initialize(list)
      @list = list
    end

    def lines(screen_width)
      return [] if @list.empty?

      list = @list.sort
      sizes = list.map { |item| Reline::Unicode.calculate_width(item) }
      item_width = sizes.max + 2
      num_cols = [screen_width / item_width, 1].max
      num_rows = list.size.fdiv(num_cols).ceil
      list_with_padding = list.zip(sizes).map { |item, size| item + ' ' * (item_width - size) }
      aligned = (list_with_padding + [nil] * (num_rows * num_cols - list_with_padding.size)).each_slice(num_rows).to_a.transpose
      aligned.map do |row|
        row.join.rstrip
      end
    end
  end

  MINIMUM_SCROLLBAR_HEIGHT = 1

  def initialize(config, encoding)
    @config = config
    @completion_append_character = ''
    @screen_size = [0, 0] # Should be initialized with actual winsize in LineEditor#reset
    reset_variables(encoding: encoding)
  end

  def io_gate
    Reline::IOGate
  end

  def set_pasting_state(in_pasting)
    # While pasting, text to be inserted is stored to @continuous_insertion_buffer.
    # After pasting, this buffer should be force inserted.
    process_insert(force: true) if @in_pasting && !in_pasting
    @in_pasting = in_pasting
  end

  private def check_mode_string
    if @config.show_mode_in_prompt
      if @config.editing_mode_is?(:vi_command)
        @config.vi_cmd_mode_string
      elsif @config.editing_mode_is?(:vi_insert)
        @config.vi_ins_mode_string
      elsif @config.editing_mode_is?(:emacs)
        @config.emacs_mode_string
      else
        '?'
      end
    end
  end

  private def check_multiline_prompt(buffer, mode_string)
    if @vi_arg
      prompt = "(arg: #{@vi_arg}) "
    elsif @searching_prompt
      prompt = @searching_prompt
    else
      prompt = @prompt
    end
    if !@is_multiline
      mode_string = check_mode_string
      prompt = mode_string + prompt if mode_string
      [prompt] + [''] * (buffer.size - 1)
    elsif @prompt_proc
      prompt_list = @prompt_proc.(buffer).map { |pr| pr.gsub("\n", "\\n") }
      prompt_list.map!{ prompt } if @vi_arg or @searching_prompt
      prompt_list = [prompt] if prompt_list.empty?
      prompt_list = prompt_list.map{ |pr| mode_string + pr } if mode_string
      prompt = prompt_list[@line_index]
      prompt = prompt_list[0] if prompt.nil?
      prompt = prompt_list.last if prompt.nil?
      if buffer.size > prompt_list.size
        (buffer.size - prompt_list.size).times do
          prompt_list << prompt_list.last
        end
      end
      prompt_list
    else
      prompt = mode_string + prompt if mode_string
      [prompt] * buffer.size
    end
  end

  def reset(prompt = '', encoding:)
    @screen_size = Reline::IOGate.get_screen_size
    reset_variables(prompt, encoding: encoding)
    @rendered_screen.base_y = Reline::IOGate.cursor_pos.y
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

  def handle_signal
    handle_interrupted
    handle_resized
  end

  private def handle_resized
    return unless @resized

    @screen_size = Reline::IOGate.get_screen_size
    @resized = false
    scroll_into_view
    Reline::IOGate.move_cursor_up @rendered_screen.cursor_y
    @rendered_screen.base_y = Reline::IOGate.cursor_pos.y
    clear_rendered_screen_cache
    render
  end

  private def handle_interrupted
    return unless @interrupted

    @interrupted = false
    clear_dialogs
    render
    cursor_to_bottom_offset = @rendered_screen.lines.size - @rendered_screen.cursor_y
    Reline::IOGate.scroll_down cursor_to_bottom_offset
    Reline::IOGate.move_cursor_column 0
    clear_rendered_screen_cache
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
  end

  def set_signal_handlers
    Reline::IOGate.set_winch_handler do
      @resized = true
    end
    @old_trap = Signal.trap('INT') do
      @interrupted = true
    end
  end

  def finalize
    Signal.trap('INT', @old_trap)
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
    @history_pointer = nil
    @kill_ring ||= Reline::KillRing.new
    @vi_clipboard = ''
    @vi_arg = nil
    @waiting_proc = nil
    @vi_waiting_operator = nil
    @vi_waiting_operator_arg = nil
    @completion_journey_state = nil
    @completion_state = CompletionState::NORMAL
    @perfect_matched = nil
    @menu_info = nil
    @searching_prompt = nil
    @just_cursor_moving = false
    @eof = false
    @continuous_insertion_buffer = String.new(encoding: @encoding)
    @scroll_partial_screen = 0
    @drop_terminate_spaces = false
    @in_pasting = false
    @auto_indent_proc = nil
    @dialogs = []
    @interrupted = false
    @resized = false
    @cache = {}
    @rendered_screen = RenderedScreen.new(base_y: 0, lines: [], cursor_y: 0)
    @input_lines = [[[""], 0, 0]]
    @input_lines_position = 0
    @undoing = false
    @prev_action_state = NullActionState
    @next_action_state = NullActionState
    reset_line
  end

  def reset_line
    @byte_pointer = 0
    @buffer_of_lines = [String.new(encoding: @encoding)]
    @line_index = 0
    @cache.clear
    @line_backup_in_history = nil
    @multibyte_buffer = String.new(encoding: 'ASCII-8BIT')
  end

  def multiline_on
    @is_multiline = true
  end

  def multiline_off
    @is_multiline = false
  end

  private def insert_new_line(cursor_line, next_line)
    @buffer_of_lines.insert(@line_index + 1, String.new(next_line, encoding: @encoding))
    @buffer_of_lines[@line_index] = cursor_line
    @line_index += 1
    @byte_pointer = 0
    if @auto_indent_proc && !@in_pasting
      if next_line.empty?
        (
          # For compatibility, use this calculation instead of just `process_auto_indent @line_index - 1, cursor_dependent: false`
          indent1 = @auto_indent_proc.(@buffer_of_lines.take(@line_index - 1).push(''), @line_index - 1, 0, true)
          indent2 = @auto_indent_proc.(@buffer_of_lines.take(@line_index), @line_index - 1, @buffer_of_lines[@line_index - 1].bytesize, false)
          indent = indent2 || indent1
          @buffer_of_lines[@line_index - 1] = ' ' * indent + @buffer_of_lines[@line_index - 1].gsub(/\A\s*/, '')
        )
        process_auto_indent @line_index, add_newline: true
      else
        process_auto_indent @line_index - 1, cursor_dependent: false
        process_auto_indent @line_index, add_newline: true # Need for compatibility
        process_auto_indent @line_index, cursor_dependent: false
      end
    end
  end

  private def split_by_width(str, max_width, offset: 0)
    Reline::Unicode.split_by_width(str, max_width, @encoding, offset: offset)
  end

  def current_byte_pointer_cursor
    calculate_width(current_line.byteslice(0, @byte_pointer))
  end

  private def calculate_nearest_cursor(cursor)
    line_to_calc = current_line
    new_cursor_max = calculate_width(line_to_calc)
    new_cursor = 0
    new_byte_pointer = 0
    height = 1
    max_width = screen_width
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
    @byte_pointer = new_byte_pointer
  end

  def with_cache(key, *deps)
    cached_deps, value = @cache[key]
    if cached_deps != deps
      @cache[key] = [deps, value = yield(*deps, cached_deps, value)]
    end
    value
  end

  def modified_lines
    with_cache(__method__, whole_lines, finished?) do |whole, complete|
      modify_lines(whole, complete)
    end
  end

  def prompt_list
    with_cache(__method__, whole_lines, check_mode_string, @vi_arg, @searching_prompt) do |lines, mode_string|
      check_multiline_prompt(lines, mode_string)
    end
  end

  def screen_height
    @screen_size.first
  end

  def screen_width
    @screen_size.last
  end

  def screen_scroll_top
    @scroll_partial_screen
  end

  def wrapped_prompt_and_input_lines
    with_cache(__method__, @buffer_of_lines.size, modified_lines, prompt_list, screen_width) do |n, lines, prompts, width, prev_cache_key, cached_value|
      prev_n, prev_lines, prev_prompts, prev_width = prev_cache_key
      cached_wraps = {}
      if prev_width == width
        prev_n.times do |i|
          cached_wraps[[prev_prompts[i], prev_lines[i]]] = cached_value[i]
        end
      end

      n.times.map do |i|
        prompt = prompts[i] || ''
        line = lines[i] || ''
        if (cached = cached_wraps[[prompt, line]])
          next cached
        end
        *wrapped_prompts, code_line_prompt = split_by_width(prompt, width).first.compact
        wrapped_lines = split_by_width(line, width, offset: calculate_width(code_line_prompt, true)).first.compact
        wrapped_prompts.map { |p| [p, ''] } + [[code_line_prompt, wrapped_lines.first]] + wrapped_lines.drop(1).map { |c| ['', c] }
      end
    end
  end

  def calculate_overlay_levels(overlay_levels)
    levels = []
    overlay_levels.each do |x, w, l|
      levels.fill(l, x, w)
    end
    levels
  end

  def render_line_differential(old_items, new_items)
    old_levels = calculate_overlay_levels(old_items.zip(new_items).each_with_index.map {|((x, w, c), (nx, _nw, nc)), i| [x, w, c == nc && x == nx ? i : -1] if x }.compact)
    new_levels = calculate_overlay_levels(new_items.each_with_index.map { |(x, w), i| [x, w, i] if x }.compact).take(screen_width)
    base_x = 0
    new_levels.zip(old_levels).chunk { |n, o| n == o ? :skip : n || :blank }.each do |level, chunk|
      width = chunk.size
      if level == :skip
        # do nothing
      elsif level == :blank
        Reline::IOGate.move_cursor_column base_x
        @output.write "#{Reline::IOGate.reset_color_sequence}#{' ' * width}"
      else
        x, w, content = new_items[level]
        cover_begin = base_x != 0 && new_levels[base_x - 1] == level
        cover_end = new_levels[base_x + width] == level
        pos = 0
        unless x == base_x && w == width
          content, pos = Reline::Unicode.take_mbchar_range(content, base_x - x, width, cover_begin: cover_begin, cover_end: cover_end, padding: true)
        end
        Reline::IOGate.move_cursor_column x + pos
        @output.write "#{Reline::IOGate.reset_color_sequence}#{content}#{Reline::IOGate.reset_color_sequence}"
      end
      base_x += width
    end
    if old_levels.size > new_levels.size
      Reline::IOGate.move_cursor_column new_levels.size
      Reline::IOGate.erase_after_cursor
    end
  end

  # Calculate cursor position in word wrapped content.
  def wrapped_cursor_position
    prompt_width = calculate_width(prompt_list[@line_index], true)
    line_before_cursor = whole_lines[@line_index].byteslice(0, @byte_pointer)
    wrapped_line_before_cursor = split_by_width(' ' * prompt_width + line_before_cursor, screen_width).first.compact
    wrapped_cursor_y = wrapped_prompt_and_input_lines[0...@line_index].sum(&:size) + wrapped_line_before_cursor.size - 1
    wrapped_cursor_x = calculate_width(wrapped_line_before_cursor.last)
    [wrapped_cursor_x, wrapped_cursor_y]
  end

  def clear_dialogs
    @dialogs.each do |dialog|
      dialog.contents = nil
      dialog.trap_key = nil
    end
  end

  def update_dialogs(key = nil)
    wrapped_cursor_x, wrapped_cursor_y = wrapped_cursor_position
    @dialogs.each do |dialog|
      dialog.trap_key = nil
      update_each_dialog(dialog, wrapped_cursor_x, wrapped_cursor_y - screen_scroll_top, key)
    end
  end

  def render_finished
    render_differential([], 0, 0)
    lines = @buffer_of_lines.size.times.map do |i|
      line = prompt_list[i] + modified_lines[i]
      wrapped_lines, = split_by_width(line, screen_width)
      wrapped_lines.last.empty? ? "#{line} " : line
    end
    @output.puts lines.map { |l| "#{l}\r\n" }.join
  end

  def print_nomultiline_prompt
    # Readline's test `TestRelineAsReadline#test_readline` requires first output to be prompt, not cursor reset escape sequence.
    @output.write @prompt if @prompt && !@is_multiline
  end

  def render
    wrapped_cursor_x, wrapped_cursor_y = wrapped_cursor_position
    new_lines = wrapped_prompt_and_input_lines.flatten(1)[screen_scroll_top, screen_height].map do |prompt, line|
      prompt_width = Reline::Unicode.calculate_width(prompt, true)
      [[0, prompt_width, prompt], [prompt_width, Reline::Unicode.calculate_width(line, true), line]]
    end
    if @menu_info
      @menu_info.lines(screen_width).each do |item|
        new_lines << [[0, Reline::Unicode.calculate_width(item), item]]
      end
      @menu_info = nil # TODO: do not change state here
    end

    @dialogs.each_with_index do |dialog, index|
      next unless dialog.contents

      x_range, y_range = dialog_range dialog, wrapped_cursor_y - screen_scroll_top
      y_range.each do |row|
        next if row < 0 || row >= screen_height

        dialog_rows = new_lines[row] ||= []
        # index 0 is for prompt, index 1 is for line, index 2.. is for dialog
        dialog_rows[index + 2] = [x_range.begin, dialog.width, dialog.contents[row - y_range.begin]]
      end
    end

    render_differential new_lines, wrapped_cursor_x, wrapped_cursor_y - screen_scroll_top
  end

  # Reflects lines to be rendered and new cursor position to the screen
  # by calculating the difference from the previous render.

  private def render_differential(new_lines, new_cursor_x, new_cursor_y)
    rendered_lines = @rendered_screen.lines
    cursor_y = @rendered_screen.cursor_y
    if new_lines != rendered_lines
      # Hide cursor while rendering to avoid cursor flickering.
      Reline::IOGate.hide_cursor
      num_lines = [[new_lines.size, rendered_lines.size].max, screen_height].min
      if @rendered_screen.base_y + num_lines > screen_height
        Reline::IOGate.scroll_down(num_lines - cursor_y - 1)
        @rendered_screen.base_y = screen_height - num_lines
        cursor_y = num_lines - 1
      end
      num_lines.times do |i|
        rendered_line = rendered_lines[i] || []
        line_to_render = new_lines[i] || []
        next if rendered_line == line_to_render

        Reline::IOGate.move_cursor_down i - cursor_y
        cursor_y = i
        unless rendered_lines[i]
          Reline::IOGate.move_cursor_column 0
          Reline::IOGate.erase_after_cursor
        end
        render_line_differential(rendered_line, line_to_render)
      end
      @rendered_screen.lines = new_lines
      Reline::IOGate.show_cursor
    end
    Reline::IOGate.move_cursor_column new_cursor_x
    Reline::IOGate.move_cursor_down new_cursor_y - cursor_y
    @rendered_screen.cursor_y = new_cursor_y
  end

  private def clear_rendered_screen_cache
    @rendered_screen.lines = []
    @rendered_screen.cursor_y = 0
  end

  def upper_space_height(wrapped_cursor_y)
    wrapped_cursor_y - screen_scroll_top
  end

  def rest_height(wrapped_cursor_y)
    screen_height - wrapped_cursor_y + screen_scroll_top - @rendered_screen.base_y - 1
  end

  def rerender
    render unless @in_pasting
  end

  class DialogProcScope
    CompletionJourneyData = Struct.new(:preposing, :postposing, :list, :pointer)

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
      @line_editor.screen_width
    end

    def screen_height
      @line_editor.screen_height
    end

    def preferred_dialog_height
      _wrapped_cursor_x, wrapped_cursor_y = @line_editor.wrapped_cursor_position
      [@line_editor.upper_space_height(wrapped_cursor_y), @line_editor.rest_height(wrapped_cursor_y), (screen_height + 6) / 5].max
    end

    def completion_journey_data
      @line_editor.dialog_proc_scope_completion_journey_data
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
    attr_accessor :scroll_top, :pointer, :column, :vertical_offset, :trap_key

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
        else
          @config.add_oneshot_key_binding(@trap_key, @name)
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

  private def dialog_range(dialog, dialog_y)
    x_range = dialog.column...dialog.column + dialog.width
    y_range = dialog_y + dialog.vertical_offset...dialog_y + dialog.vertical_offset + dialog.contents.size
    [x_range, y_range]
  end

  private def update_each_dialog(dialog, cursor_column, cursor_row, key = nil)
    dialog.set_cursor_pos(cursor_column, cursor_row)
    dialog_render_info = dialog.call(key)
    if dialog_render_info.nil? or dialog_render_info.contents.nil? or dialog_render_info.contents.empty?
      dialog.contents = nil
      dialog.trap_key = nil
      return
    end
    contents = dialog_render_info.contents
    pointer = dialog.pointer
    if dialog_render_info.width
      dialog.width = dialog_render_info.width
    else
      dialog.width = contents.map { |l| calculate_width(l, true) }.max
    end
    height = dialog_render_info.height || DIALOG_DEFAULT_HEIGHT
    height = contents.size if contents.size < height
    if contents.size > height
      if dialog.pointer
        if dialog.pointer < 0
          dialog.scroll_top = 0
        elsif (dialog.pointer - dialog.scroll_top) >= (height - 1)
          dialog.scroll_top = dialog.pointer - (height - 1)
        elsif (dialog.pointer - dialog.scroll_top) < 0
          dialog.scroll_top = dialog.pointer
        end
        pointer = dialog.pointer - dialog.scroll_top
      else
        dialog.scroll_top = 0
      end
      contents = contents[dialog.scroll_top, height]
    end
    if dialog_render_info.scrollbar and dialog_render_info.contents.size > height
      bar_max_height = height * 2
      moving_distance = (dialog_render_info.contents.size - height) * 2
      position_ratio = dialog.scroll_top.zero? ? 0.0 : ((dialog.scroll_top * 2).to_f / moving_distance)
      bar_height = (bar_max_height * ((contents.size * 2).to_f / (dialog_render_info.contents.size * 2))).floor.to_i
      bar_height = MINIMUM_SCROLLBAR_HEIGHT if bar_height < MINIMUM_SCROLLBAR_HEIGHT
      scrollbar_pos = ((bar_max_height - bar_height) * position_ratio).floor.to_i
    else
      scrollbar_pos = nil
    end
    dialog.column = dialog_render_info.pos.x
    dialog.width += @block_elem_width if scrollbar_pos
    diff = (dialog.column + dialog.width) - screen_width
    if diff > 0
      dialog.column -= diff
    end
    if rest_height(screen_scroll_top + cursor_row) - dialog_render_info.pos.y >= height
      dialog.vertical_offset = dialog_render_info.pos.y + 1
    elsif cursor_row >= height
      dialog.vertical_offset = dialog_render_info.pos.y - height
    else
      dialog.vertical_offset = dialog_render_info.pos.y + 1
    end
    if dialog.column < 0
      dialog.column = 0
      dialog.width = screen_width
    end
    face = Reline::Face[dialog_render_info.face || :default]
    scrollbar_sgr = face[:scrollbar]
    default_sgr = face[:default]
    enhanced_sgr = face[:enhanced]
    dialog.contents = contents.map.with_index do |item, i|
      line_sgr = i == pointer ? enhanced_sgr : default_sgr
      str_width = dialog.width - (scrollbar_pos.nil? ? 0 : @block_elem_width)
      str, = Reline::Unicode.take_mbchar_range(item, 0, str_width, padding: true)
      colored_content = "#{line_sgr}#{str}"
      if scrollbar_pos
        if scrollbar_pos <= (i * 2) and (i * 2 + 1) < (scrollbar_pos + bar_height)
          colored_content + scrollbar_sgr + @full_block
        elsif scrollbar_pos <= (i * 2) and (i * 2) < (scrollbar_pos + bar_height)
          colored_content + scrollbar_sgr + @upper_half_block
        elsif scrollbar_pos <= (i * 2 + 1) and (i * 2) < (scrollbar_pos + bar_height)
          colored_content + scrollbar_sgr + @lower_half_block
        else
          colored_content + scrollbar_sgr + ' ' * @block_elem_width
        end
      else
        colored_content
      end
    end
  end

  private def modify_lines(before, complete)
    if after = @output_modifier_proc&.call("#{before.join("\n")}\n", complete: complete)
      after.lines("\n").map { |l| l.chomp('') }
    else
      before.map { |l| Reline::Unicode.escape_for_print(l) }
    end
  end

  def editing_mode
    @config.editing_mode
  end

  private def menu(_target, list)
    @menu_info = MenuInfo.new(list)
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
      result = +''
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

  private def perform_completion(list, just_show_list)
    case @completion_state
    when CompletionState::NORMAL
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
          perform_completion(list, true) if @config.show_all_if_ambiguous
        end
        @perfect_matched = completed
      else
        @completion_state = CompletionState::MENU
        perform_completion(list, true) if @config.show_all_if_ambiguous
      end
      if not just_show_list and target < completed
        @buffer_of_lines[@line_index] = (preposing + completed + completion_append_character.to_s + postposing).split("\n")[@line_index] || String.new(encoding: @encoding)
        line_to_pointer = (preposing + completed + completion_append_character.to_s).split("\n")[@line_index] || String.new(encoding: @encoding)
        @byte_pointer = line_to_pointer.bytesize
      end
    end
  end

  def dialog_proc_scope_completion_journey_data
    return nil unless @completion_journey_state
    line_index = @completion_journey_state.line_index
    pre_lines = @buffer_of_lines[0...line_index].map { |line| line + "\n" }
    post_lines = @buffer_of_lines[(line_index + 1)..-1].map { |line| line + "\n" }
    DialogProcScope::CompletionJourneyData.new(
      pre_lines.join + @completion_journey_state.pre,
      @completion_journey_state.post + post_lines.join,
      @completion_journey_state.list,
      @completion_journey_state.pointer
    )
  end

  private def move_completed_list(direction)
    @completion_journey_state ||= retrieve_completion_journey_state
    return false unless @completion_journey_state

    if (delta = { up: -1, down: +1 }[direction])
      @completion_journey_state.pointer = (@completion_journey_state.pointer + delta) % @completion_journey_state.list.size
    end
    completed = @completion_journey_state.list[@completion_journey_state.pointer]
    set_current_line(@completion_journey_state.pre + completed + @completion_journey_state.post, @completion_journey_state.pre.bytesize + completed.bytesize)
    true
  end

  private def retrieve_completion_journey_state
    preposing, target, postposing = retrieve_completion_block
    list = call_completion_proc
    return unless list.is_a?(Array)

    candidates = list.select{ |item| item.start_with?(target) }
    return if candidates.empty?

    pre = preposing.split("\n", -1).last || ''
    post = postposing.split("\n", -1).first || ''
    CompletionJourneyState.new(
      @line_index, pre, target, post, [target] + candidates, 0
    )
  end

  private def run_for_operators(key, method_symbol, &block)
    if @vi_waiting_operator
      if VI_MOTIONS.include?(method_symbol)
        old_byte_pointer = @byte_pointer
        @vi_arg = (@vi_arg || 1) * @vi_waiting_operator_arg
        block.(true)
        unless @waiting_proc
          byte_pointer_diff = @byte_pointer - old_byte_pointer
          @byte_pointer = old_byte_pointer
          method_obj = method(@vi_waiting_operator)
          wrap_method_call(@vi_waiting_operator, method_obj, byte_pointer_diff)
          cleanup_waiting
        end
      else
        # Ignores operator when not motion is given.
        block.(false)
        cleanup_waiting
      end
      @vi_arg = nil
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
    if @config.editing_mode_is?(:emacs, :vi_insert) and @vi_waiting_operator.nil?
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

  private def cleanup_waiting
    @waiting_proc = nil
    @vi_waiting_operator = nil
    @vi_waiting_operator_arg = nil
    @searching_prompt = nil
    @drop_terminate_spaces = false
  end

  private def process_key(key, method_symbol)
    if key.is_a?(Symbol)
      cleanup_waiting
    elsif @waiting_proc
      old_byte_pointer = @byte_pointer
      @waiting_proc.call(key)
      if @vi_waiting_operator
        byte_pointer_diff = @byte_pointer - old_byte_pointer
        @byte_pointer = old_byte_pointer
        method_obj = method(@vi_waiting_operator)
        wrap_method_call(@vi_waiting_operator, method_obj, byte_pointer_diff)
        cleanup_waiting
      end
      @kill_ring.process
      return
    end

    if method_symbol and respond_to?(method_symbol, true)
      method_obj = method(method_symbol)
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
        elsif method_obj
          wrap_method_call(method_symbol, method_obj, key)
        else
          ed_insert(key) unless @config.editing_mode_is?(:vi_command)
        end
        @kill_ring.process
        if @vi_arg
          @vi_arg = nil
        end
      end
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
      process_key(key.combined_char, method_symbol)
      @multibyte_buffer.clear
    end
    if @config.editing_mode_is?(:vi_command) and @byte_pointer > 0 and @byte_pointer == current_line.bytesize
      byte_size = Reline::Unicode.get_prev_mbchar_size(@buffer_of_lines[@line_index], @byte_pointer)
      @byte_pointer -= byte_size
    end
  end

  def update(key)
    modified = input_key(key)
    unless @in_pasting
      scroll_into_view
      @just_cursor_moving = !modified
      update_dialogs(key)
      @just_cursor_moving = false
    end
  end

  def input_key(key)
    save_old_buffer
    @config.reset_oneshot_key_bindings
    @dialogs.each do |dialog|
      if key.char.instance_of?(Symbol) and key.char == dialog.name
        return
      end
    end
    if key.char.nil?
      process_insert(force: true)
      @eof = buffer_empty?
      finish
      return
    end
    @completion_occurs = false

    if key.char.is_a?(Symbol)
      process_key(key.char, key.char)
    else
      normal_char(key)
    end

    @prev_action_state, @next_action_state = @next_action_state, NullActionState

    unless @completion_occurs
      @completion_state = CompletionState::NORMAL
      @completion_journey_state = nil
    end

    push_input_lines unless @undoing
    @undoing = false

    if @in_pasting
      clear_dialogs
      return
    end

    modified = @old_buffer_of_lines != @buffer_of_lines
    if !@completion_occurs && modified && !@config.disable_completion && @config.autocompletion
      # Auto complete starts only when edited
      process_insert(force: true)
      @completion_journey_state = retrieve_completion_journey_state
    end
    modified
  end

  def save_old_buffer
    @old_buffer_of_lines = @buffer_of_lines.dup
  end

  def push_input_lines
    if @old_buffer_of_lines == @buffer_of_lines
      @input_lines[@input_lines_position] = [@buffer_of_lines.dup, @byte_pointer, @line_index]
    else
      @input_lines = @input_lines[0..@input_lines_position]
      @input_lines_position += 1
      @input_lines.push([@buffer_of_lines.dup, @byte_pointer, @line_index])
    end
    trim_input_lines
  end

  MAX_INPUT_LINES = 100
  def trim_input_lines
    if @input_lines.size > MAX_INPUT_LINES
      @input_lines.shift
      @input_lines_position -= 1
    end
  end

  def scroll_into_view
    _wrapped_cursor_x, wrapped_cursor_y = wrapped_cursor_position
    if wrapped_cursor_y < screen_scroll_top
      @scroll_partial_screen = wrapped_cursor_y
    end
    if wrapped_cursor_y >= screen_scroll_top + screen_height
      @scroll_partial_screen = wrapped_cursor_y - screen_height + 1
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

  private def process_auto_indent(line_index = @line_index, cursor_dependent: true, add_newline: false)
    return if @in_pasting
    return unless @auto_indent_proc

    line = @buffer_of_lines[line_index]
    byte_pointer = cursor_dependent && @line_index == line_index ? @byte_pointer : line.bytesize
    new_indent = @auto_indent_proc.(@buffer_of_lines.take(line_index + 1).push(''), line_index, byte_pointer, add_newline)
    return unless new_indent

    new_line = ' ' * new_indent + line.lstrip
    @buffer_of_lines[line_index] = new_line
    if @line_index == line_index
      indent_diff = new_line.bytesize - line.bytesize
      @byte_pointer = [@byte_pointer + indent_diff, 0].max
    end
  end

  def line()
    @buffer_of_lines.join("\n") unless eof?
  end

  def current_line
    @buffer_of_lines[@line_index]
  end

  def set_current_line(line, byte_pointer = nil)
    cursor = current_byte_pointer_cursor
    @buffer_of_lines[@line_index] = line
    if byte_pointer
      @byte_pointer = byte_pointer
    else
      calculate_nearest_cursor(cursor)
    end
    process_auto_indent
  end

  def set_current_lines(lines, byte_pointer = nil, line_index = 0)
    cursor = current_byte_pointer_cursor
    @buffer_of_lines = lines
    @line_index = line_index
    if byte_pointer
      @byte_pointer = byte_pointer
    else
      calculate_nearest_cursor(cursor)
    end
    process_auto_indent
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
    before = current_line.byteslice(0, @byte_pointer)
    rest = nil
    break_pointer = nil
    quote = nil
    closing_quote = nil
    escaped_quote = nil
    i = 0
    while i < @byte_pointer do
      slice = current_line.byteslice(i, @byte_pointer - i)
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
        before = current_line.byteslice(i, @byte_pointer - i)
        break_pointer = i
      else
        i += 1
      end
    end
    postposing = current_line.byteslice(@byte_pointer, current_line.bytesize - @byte_pointer)
    if rest
      preposing = current_line.byteslice(0, break_pointer)
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
        preposing = current_line.byteslice(0, break_pointer)
      else
        preposing = ''
      end
      target = before
    end
    lines = whole_lines
    if @line_index > 0
      preposing = lines[0..(@line_index - 1)].join("\n") + "\n" + preposing
    end
    if (lines.size - 1) > @line_index
      postposing = postposing + "\n" + lines[(@line_index + 1)..-1].join("\n")
    end
    [preposing.encode(@encoding), target.encode(@encoding), postposing.encode(@encoding)]
  end

  def confirm_multiline_termination
    temp_buffer = @buffer_of_lines.dup
    @confirm_multiline_termination_proc.(temp_buffer.join("\n") + "\n")
  end

  def insert_multiline_text(text)
    save_old_buffer
    pre = @buffer_of_lines[@line_index].byteslice(0, @byte_pointer)
    post = @buffer_of_lines[@line_index].byteslice(@byte_pointer..)
    lines = (pre + text.gsub(/\r\n?/, "\n") + post).split("\n", -1)
    lines << '' if lines.empty?
    @buffer_of_lines[@line_index, 1] = lines
    @line_index += lines.size - 1
    @byte_pointer = @buffer_of_lines[@line_index].bytesize - post.bytesize
    push_input_lines
  end

  def insert_text(text)
    if @buffer_of_lines[@line_index].bytesize == @byte_pointer
      @buffer_of_lines[@line_index] += text
    else
      @buffer_of_lines[@line_index] = byteinsert(@buffer_of_lines[@line_index], @byte_pointer, text)
    end
    @byte_pointer += text.bytesize
    process_auto_indent
  end

  def delete_text(start = nil, length = nil)
    if start.nil? and length.nil?
      if @buffer_of_lines.size == 1
        @buffer_of_lines[@line_index] = ''
        @byte_pointer = 0
      elsif @line_index == (@buffer_of_lines.size - 1) and @line_index > 0
        @buffer_of_lines.pop
        @line_index -= 1
        @byte_pointer = 0
      elsif @line_index < (@buffer_of_lines.size - 1)
        @buffer_of_lines.delete_at(@line_index)
        @byte_pointer = 0
      end
    elsif not start.nil? and not length.nil?
      if current_line
        before = current_line.byteslice(0, start)
        after = current_line.byteslice(start + length, current_line.bytesize)
        set_current_line(before + after)
      end
    elsif start.is_a?(Range)
      range = start
      first = range.first
      last = range.last
      last = current_line.bytesize - 1 if last > current_line.bytesize
      last += current_line.bytesize if last < 0
      first += current_line.bytesize if first < 0
      range = range.exclude_end? ? first...last : first..last
      line = current_line.bytes.reject.with_index{ |c, i| range.include?(i) }.map{ |c| c.chr(Encoding::ASCII_8BIT) }.join.force_encoding(@encoding)
      set_current_line(line)
    else
      set_current_line(current_line.byteslice(0, start))
    end
  end

  def byte_pointer=(val)
    @byte_pointer = val
  end

  def whole_lines
    @buffer_of_lines.dup
  end

  def whole_buffer
    whole_lines.join("\n")
  end

  private def buffer_empty?
    current_line.empty? and @buffer_of_lines.size == 1
  end

  def finished?
    @finished
  end

  def finish
    @finished = true
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
    if @config.editing_mode_is?(:vi_insert)
      ed_delete_next_char(key)
    elsif @config.editing_mode_is?(:emacs)
      em_delete(key)
    end
  end

  private def key_newline(key)
    if @is_multiline
      next_line = current_line.byteslice(@byte_pointer, current_line.bytesize - @byte_pointer)
      cursor_line = current_line.byteslice(0, @byte_pointer)
      insert_new_line(cursor_line, next_line)
    end
  end

  private def complete(_key)
    return if @config.disable_completion

    process_insert(force: true)
    if @config.autocompletion
      @completion_state = CompletionState::NORMAL
      @completion_occurs = move_completed_list(:down)
    else
      @completion_journey_state = nil
      result = call_completion_proc
      if result.is_a?(Array)
        @completion_occurs = true
        perform_completion(result, false)
      end
    end
  end

  private def completion_journey_move(direction)
    return if @config.disable_completion

    process_insert(force: true)
    @completion_state = CompletionState::NORMAL
    @completion_occurs = move_completed_list(direction)
  end

  private def menu_complete(_key)
    completion_journey_move(:down)
  end

  private def menu_complete_backward(_key)
    completion_journey_move(:up)
  end

  private def completion_journey_up(_key)
    completion_journey_move(:up) if @config.autocompletion
  end

  # Editline:: +ed-unassigned+ This  editor command always results in an error.
  # GNU Readline:: There is no corresponding macro.
  private def ed_unassigned(key) end # do nothing

  private def process_insert(force: false)
    return if @continuous_insertion_buffer.empty? or (@in_pasting and not force)
    insert_text(@continuous_insertion_buffer)
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
    if key.instance_of?(String)
      begin
        key.encode(Encoding::UTF_8)
      rescue Encoding::UndefinedConversionError
        return
      end
      str = key
    else
      begin
        key.chr.encode(Encoding::UTF_8)
      rescue Encoding::UndefinedConversionError
        return
      end
      str = key.chr
    end
    if @in_pasting
      @continuous_insertion_buffer << str
      return
    elsif not @continuous_insertion_buffer.empty?
      process_insert
    end

    insert_text(str)
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
    byte_size = Reline::Unicode.get_next_mbchar_size(current_line, @byte_pointer)
    if (@byte_pointer < current_line.bytesize)
      @byte_pointer += byte_size
    elsif @config.editing_mode_is?(:emacs) and @byte_pointer == current_line.bytesize and @line_index < @buffer_of_lines.size - 1
      @byte_pointer = 0
      @line_index += 1
    end
    arg -= 1
    ed_next_char(key, arg: arg) if arg > 0
  end
  alias_method :forward_char, :ed_next_char

  private def ed_prev_char(key, arg: 1)
    if @byte_pointer > 0
      byte_size = Reline::Unicode.get_prev_mbchar_size(current_line, @byte_pointer)
      @byte_pointer -= byte_size
    elsif @config.editing_mode_is?(:emacs) and @byte_pointer == 0 and @line_index > 0
      @line_index -= 1
      @byte_pointer = current_line.bytesize
    end
    arg -= 1
    ed_prev_char(key, arg: arg) if arg > 0
  end
  alias_method :backward_char, :ed_prev_char

  private def vi_first_print(key)
    @byte_pointer, = Reline::Unicode.vi_first_print(current_line)
  end

  private def ed_move_to_beg(key)
    @byte_pointer = 0
  end
  alias_method :beginning_of_line, :ed_move_to_beg
  alias_method :vi_zero, :ed_move_to_beg

  private def ed_move_to_end(key)
    @byte_pointer = current_line.bytesize
  end
  alias_method :end_of_line, :ed_move_to_end

  private def generate_searcher(search_key)
    search_word = String.new(encoding: @encoding)
    multibyte_buf = String.new(encoding: 'ASCII-8BIT')
    hit_pointer = nil
    lambda do |key|
      search_again = false
      case key
      when "\C-h".ord, "\C-?".ord
        grapheme_clusters = search_word.grapheme_clusters
        if grapheme_clusters.size > 0
          grapheme_clusters.pop
          search_word = grapheme_clusters.join
        end
      when "\C-r".ord, "\C-s".ord
        search_again = true if search_key == key
        search_key = key
      else
        multibyte_buf << key
        if multibyte_buf.dup.force_encoding(@encoding).valid_encoding?
          search_word << multibyte_buf.dup.force_encoding(@encoding)
          multibyte_buf.clear
        end
      end
      hit = nil
      if not search_word.empty? and @line_backup_in_history&.include?(search_word)
        hit_pointer = Reline::HISTORY.size
        hit = @line_backup_in_history
      else
        if search_again
          if search_word.empty? and Reline.last_incremental_search
            search_word = Reline.last_incremental_search
          end
          if @history_pointer
            case search_key
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
          case search_key
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
        case search_key
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
          hit_pointer = history_pointer_base + hit_index
          hit = Reline::HISTORY[hit_pointer]
        end
      end
      case search_key
      when "\C-r".ord
        prompt_name = 'reverse-i-search'
      when "\C-s".ord
        prompt_name = 'i-search'
      end
      prompt_name = "failed #{prompt_name}" unless hit
      [search_word, prompt_name, hit_pointer]
    end
  end

  private def incremental_search_history(key)
    unless @history_pointer
      @line_backup_in_history = whole_buffer
    end
    searcher = generate_searcher(key)
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
        @buffer_of_lines = buffer.split("\n")
        @buffer_of_lines = [String.new(encoding: @encoding)] if @buffer_of_lines.empty?
        @line_index = @buffer_of_lines.size - 1
        @searching_prompt = nil
        @waiting_proc = nil
        @byte_pointer = 0
      when "\C-g".ord
        @buffer_of_lines = @line_backup_in_history.split("\n")
        @buffer_of_lines = [String.new(encoding: @encoding)] if @buffer_of_lines.empty?
        @line_index = @buffer_of_lines.size - 1
        move_history(nil, line: :end, cursor: :end, save_buffer: false)
        @searching_prompt = nil
        @waiting_proc = nil
        @byte_pointer = 0
      else
        chr = k.is_a?(String) ? k : k.chr(Encoding::ASCII_8BIT)
        if chr.match?(/[[:print:]]/) or k == "\C-h".ord or k == "\C-?".ord or k == "\C-r".ord or k == "\C-s".ord
          search_word, prompt_name, hit_pointer = searcher.call(k)
          Reline.last_incremental_search = search_word
          @searching_prompt = "(%s)`%s'" % [prompt_name, search_word]
          @searching_prompt += ': ' unless @is_multiline
          move_history(hit_pointer, line: :end, cursor: :end, save_buffer: false) if hit_pointer
        else
          if @history_pointer
            line = Reline::HISTORY[@history_pointer]
          else
            line = @line_backup_in_history
          end
          @line_backup_in_history = whole_buffer
          @buffer_of_lines = line.split("\n")
          @buffer_of_lines = [String.new(encoding: @encoding)] if @buffer_of_lines.empty?
          @line_index = @buffer_of_lines.size - 1
          @searching_prompt = nil
          @waiting_proc = nil
          @byte_pointer = 0
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

  private def search_history(prefix, pointer_range)
    pointer_range.each do |pointer|
      lines = Reline::HISTORY[pointer].split("\n")
      lines.each_with_index do |line, index|
        return [pointer, index] if line.start_with?(prefix)
      end
    end
    nil
  end

  private def ed_search_prev_history(key, arg: 1)
    substr = prev_action_state_value(:search_history) == :empty ? '' : current_line.byteslice(0, @byte_pointer)
    return if @history_pointer == 0
    return if @history_pointer.nil? && substr.empty? && !current_line.empty?

    history_range = 0...(@history_pointer || Reline::HISTORY.size)
    h_pointer, line_index = search_history(substr, history_range.reverse_each)
    return unless h_pointer
    move_history(h_pointer, line: line_index || :start, cursor: substr.empty? ? :end : @byte_pointer)
    arg -= 1
    set_next_action_state(:search_history, :empty) if substr.empty?
    ed_search_prev_history(key, arg: arg) if arg > 0
  end
  alias_method :history_search_backward, :ed_search_prev_history

  private def ed_search_next_history(key, arg: 1)
    substr = prev_action_state_value(:search_history) == :empty ? '' : current_line.byteslice(0, @byte_pointer)
    return if @history_pointer.nil?

    history_range = @history_pointer + 1...Reline::HISTORY.size
    h_pointer, line_index = search_history(substr, history_range)
    return if h_pointer.nil? and not substr.empty?

    move_history(h_pointer, line: line_index || :start, cursor: substr.empty? ? :end : @byte_pointer)
    arg -= 1
    set_next_action_state(:search_history, :empty) if substr.empty?
    ed_search_next_history(key, arg: arg) if arg > 0
  end
  alias_method :history_search_forward, :ed_search_next_history

  private def move_history(history_pointer, line:, cursor:, save_buffer: true)
    history_pointer ||= Reline::HISTORY.size
    return if history_pointer < 0 || history_pointer > Reline::HISTORY.size
    old_history_pointer = @history_pointer || Reline::HISTORY.size
    if old_history_pointer == Reline::HISTORY.size
      @line_backup_in_history = save_buffer ? whole_buffer : ''
    else
      Reline::HISTORY[old_history_pointer] = whole_buffer if save_buffer
    end
    if history_pointer == Reline::HISTORY.size
      buf = @line_backup_in_history
      @history_pointer = @line_backup_in_history = nil
    else
      buf = Reline::HISTORY[history_pointer]
      @history_pointer = history_pointer
    end
    @buffer_of_lines = buf.split("\n")
    @buffer_of_lines = [String.new(encoding: @encoding)] if @buffer_of_lines.empty?
    @line_index = line == :start ? 0 : line == :end ? @buffer_of_lines.size - 1 : line
    @byte_pointer = cursor == :start ? 0 : cursor == :end ? current_line.bytesize : cursor
  end

  private def ed_prev_history(key, arg: 1)
    if @line_index > 0
      cursor = current_byte_pointer_cursor
      @line_index -= 1
      calculate_nearest_cursor(cursor)
      return
    end
    move_history(
      (@history_pointer || Reline::HISTORY.size) - 1,
      line: :end,
      cursor: @config.editing_mode_is?(:vi_command) ? :start : :end,
    )
    arg -= 1
    ed_prev_history(key, arg: arg) if arg > 0
  end
  alias_method :previous_history, :ed_prev_history

  private def ed_next_history(key, arg: 1)
    if @line_index < (@buffer_of_lines.size - 1)
      cursor = current_byte_pointer_cursor
      @line_index += 1
      calculate_nearest_cursor(cursor)
      return
    end
    move_history(
      (@history_pointer || Reline::HISTORY.size) + 1,
      line: :start,
      cursor: @config.editing_mode_is?(:vi_command) ? :start : :end,
    )
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
          @line_index = @buffer_of_lines.size - 1
          @byte_pointer = current_line.bytesize
          finish
        end
      end
    else
      finish
    end
  end

  private def em_delete_prev_char(key, arg: 1)
    arg.times do
      if @byte_pointer == 0 and @line_index > 0
        @byte_pointer = @buffer_of_lines[@line_index - 1].bytesize
        @buffer_of_lines[@line_index - 1] += @buffer_of_lines.delete_at(@line_index)
        @line_index -= 1
      elsif @byte_pointer > 0
        byte_size = Reline::Unicode.get_prev_mbchar_size(current_line, @byte_pointer)
        line, = byteslice!(current_line, @byte_pointer - byte_size, byte_size)
        set_current_line(line, @byte_pointer - byte_size)
      end
    end
    process_auto_indent
  end
  alias_method :backward_delete_char, :em_delete_prev_char

  # Editline:: +ed-kill-line+ (vi command: +D+, +Ctrl-K+; emacs: +Ctrl-K+,
  #            +Ctrl-U+) + Kill from the cursor to the end of the line.
  # GNU Readline:: +kill-line+ (+C-k+) Kill the text from point to the end of
  #                the line. With a negative numeric argument, kill backward
  #                from the cursor to the beginning of the current line.
  private def ed_kill_line(key)
    if current_line.bytesize > @byte_pointer
      line, deleted = byteslice!(current_line, @byte_pointer, current_line.bytesize - @byte_pointer)
      set_current_line(line, line.bytesize)
      @kill_ring.append(deleted)
    elsif @byte_pointer == current_line.bytesize and @buffer_of_lines.size > @line_index + 1
      set_current_line(current_line + @buffer_of_lines.delete_at(@line_index + 1), current_line.bytesize)
    end
  end
  alias_method :kill_line, :ed_kill_line

  # Editline:: +vi_change_to_eol+ (vi command: +C+) + Kill and change from the cursor to the end of the line.
  private def vi_change_to_eol(key)
    ed_kill_line(key)

    @config.editing_mode = :vi_insert
  end

  # Editline:: +vi-kill-line-prev+ (vi: +Ctrl-U+) Delete the string from the
  #            beginning  of the edit buffer to the cursor and save it to the
  #            cut buffer.
  # GNU Readline:: +unix-line-discard+ (+C-u+) Kill backward from the cursor
  #                to the beginning of the current line.
  private def vi_kill_line_prev(key)
    if @byte_pointer > 0
      line, deleted = byteslice!(current_line, 0, @byte_pointer)
      set_current_line(line, 0)
      @kill_ring.append(deleted, true)
    end
  end
  alias_method :unix_line_discard, :vi_kill_line_prev

  # Editline:: +em-kill-line+ (not bound) Delete the entire contents of the
  #            edit buffer and save it to the cut buffer. +vi-kill-line-prev+
  # GNU Readline:: +kill-whole-line+ (not bound) Kill all characters on the
  #                current line, no matter where point is.
  private def em_kill_line(key)
    if current_line.size > 0
      @kill_ring.append(current_line.dup, true)
      set_current_line('', 0)
    end
  end
  alias_method :kill_whole_line, :em_kill_line

  private def em_delete(key)
    if buffer_empty? and key == "\C-d".ord
      @eof = true
      finish
    elsif @byte_pointer < current_line.bytesize
      splitted_last = current_line.byteslice(@byte_pointer, current_line.bytesize)
      mbchar = splitted_last.grapheme_clusters.first
      line, = byteslice!(current_line, @byte_pointer, mbchar.bytesize)
      set_current_line(line)
    elsif @byte_pointer == current_line.bytesize and @buffer_of_lines.size > @line_index + 1
      set_current_line(current_line + @buffer_of_lines.delete_at(@line_index + 1), current_line.bytesize)
    end
  end
  alias_method :delete_char, :em_delete

  private def em_delete_or_list(key)
    if current_line.empty? or @byte_pointer < current_line.bytesize
      em_delete(key)
    elsif !@config.autocompletion # show completed list
      result = call_completion_proc
      if result.is_a?(Array)
        perform_completion(result, true)
      end
    end
  end
  alias_method :delete_char_or_list, :em_delete_or_list

  private def em_yank(key)
    yanked = @kill_ring.yank
    insert_text(yanked) if yanked
  end
  alias_method :yank, :em_yank

  private def em_yank_pop(key)
    yanked, prev_yank = @kill_ring.yank_pop
    if yanked
      line, = byteslice!(current_line, @byte_pointer - prev_yank.bytesize, prev_yank.bytesize)
      set_current_line(line, @byte_pointer - prev_yank.bytesize)
      insert_text(yanked)
    end
  end
  alias_method :yank_pop, :em_yank_pop

  private def ed_clear_screen(key)
    Reline::IOGate.clear_screen
    @screen_size = Reline::IOGate.get_screen_size
    @rendered_screen.base_y = 0
    clear_rendered_screen_cache
  end
  alias_method :clear_screen, :ed_clear_screen

  private def em_next_word(key)
    if current_line.bytesize > @byte_pointer
      byte_size, _ = Reline::Unicode.em_forward_word(current_line, @byte_pointer)
      @byte_pointer += byte_size
    end
  end
  alias_method :forward_word, :em_next_word

  private def ed_prev_word(key)
    if @byte_pointer > 0
      byte_size, _ = Reline::Unicode.em_backward_word(current_line, @byte_pointer)
      @byte_pointer -= byte_size
    end
  end
  alias_method :backward_word, :ed_prev_word

  private def em_delete_next_word(key)
    if current_line.bytesize > @byte_pointer
      byte_size, _ = Reline::Unicode.em_forward_word(current_line, @byte_pointer)
      line, word = byteslice!(current_line, @byte_pointer, byte_size)
      set_current_line(line)
      @kill_ring.append(word)
    end
  end
  alias_method :kill_word, :em_delete_next_word

  private def ed_delete_prev_word(key)
    if @byte_pointer > 0
      byte_size, _ = Reline::Unicode.em_backward_word(current_line, @byte_pointer)
      line, word = byteslice!(current_line, @byte_pointer - byte_size, byte_size)
      set_current_line(line, @byte_pointer - byte_size)
      @kill_ring.append(word, true)
    end
  end
  alias_method :backward_kill_word, :ed_delete_prev_word

  private def ed_transpose_chars(key)
    if @byte_pointer > 0
      if @byte_pointer < current_line.bytesize
        byte_size = Reline::Unicode.get_next_mbchar_size(current_line, @byte_pointer)
        @byte_pointer += byte_size
      end
      back1_byte_size = Reline::Unicode.get_prev_mbchar_size(current_line, @byte_pointer)
      if (@byte_pointer - back1_byte_size) > 0
        back2_byte_size = Reline::Unicode.get_prev_mbchar_size(current_line, @byte_pointer - back1_byte_size)
        back2_pointer = @byte_pointer - back1_byte_size - back2_byte_size
        line, back2_mbchar = byteslice!(current_line, back2_pointer, back2_byte_size)
        set_current_line(byteinsert(line, @byte_pointer - back2_byte_size, back2_mbchar))
      end
    end
  end
  alias_method :transpose_chars, :ed_transpose_chars

  private def ed_transpose_words(key)
    left_word_start, middle_start, right_word_start, after_start = Reline::Unicode.ed_transpose_words(current_line, @byte_pointer)
    before = current_line.byteslice(0, left_word_start)
    left_word = current_line.byteslice(left_word_start, middle_start - left_word_start)
    middle = current_line.byteslice(middle_start, right_word_start - middle_start)
    right_word = current_line.byteslice(right_word_start, after_start - right_word_start)
    after = current_line.byteslice(after_start, current_line.bytesize - after_start)
    return if left_word.empty? or right_word.empty?
    from_head_to_left_word = before + right_word + middle + left_word
    set_current_line(from_head_to_left_word + after, from_head_to_left_word.bytesize)
  end
  alias_method :transpose_words, :ed_transpose_words

  private def em_capitol_case(key)
    if current_line.bytesize > @byte_pointer
      byte_size, _, new_str = Reline::Unicode.em_forward_word_with_capitalization(current_line, @byte_pointer)
      before = current_line.byteslice(0, @byte_pointer)
      after = current_line.byteslice((@byte_pointer + byte_size)..-1)
      set_current_line(before + new_str + after, @byte_pointer + new_str.bytesize)
    end
  end
  alias_method :capitalize_word, :em_capitol_case

  private def em_lower_case(key)
    if current_line.bytesize > @byte_pointer
      byte_size, = Reline::Unicode.em_forward_word(current_line, @byte_pointer)
      part = current_line.byteslice(@byte_pointer, byte_size).grapheme_clusters.map { |mbchar|
        mbchar =~ /[A-Z]/ ? mbchar.downcase : mbchar
      }.join
      rest = current_line.byteslice((@byte_pointer + byte_size)..-1)
      line = current_line.byteslice(0, @byte_pointer) + part
      set_current_line(line + rest, line.bytesize)
    end
  end
  alias_method :downcase_word, :em_lower_case

  private def em_upper_case(key)
    if current_line.bytesize > @byte_pointer
      byte_size, = Reline::Unicode.em_forward_word(current_line, @byte_pointer)
      part = current_line.byteslice(@byte_pointer, byte_size).grapheme_clusters.map { |mbchar|
        mbchar =~ /[a-z]/ ? mbchar.upcase : mbchar
      }.join
      rest = current_line.byteslice((@byte_pointer + byte_size)..-1)
      line = current_line.byteslice(0, @byte_pointer) + part
      set_current_line(line + rest, line.bytesize)
    end
  end
  alias_method :upcase_word, :em_upper_case

  private def em_kill_region(key)
    if @byte_pointer > 0
      byte_size, _ = Reline::Unicode.em_big_backward_word(current_line, @byte_pointer)
      line, deleted = byteslice!(current_line, @byte_pointer - byte_size, byte_size)
      set_current_line(line, @byte_pointer - byte_size)
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
    if current_line.bytesize > @byte_pointer
      byte_size, _ = Reline::Unicode.vi_forward_word(current_line, @byte_pointer, @drop_terminate_spaces)
      @byte_pointer += byte_size
    end
    arg -= 1
    vi_next_word(key, arg: arg) if arg > 0
  end

  private def vi_prev_word(key, arg: 1)
    if @byte_pointer > 0
      byte_size, _ = Reline::Unicode.vi_backward_word(current_line, @byte_pointer)
      @byte_pointer -= byte_size
    end
    arg -= 1
    vi_prev_word(key, arg: arg) if arg > 0
  end

  private def vi_end_word(key, arg: 1, inclusive: false)
    if current_line.bytesize > @byte_pointer
      byte_size, _ = Reline::Unicode.vi_forward_end_word(current_line, @byte_pointer)
      @byte_pointer += byte_size
    end
    arg -= 1
    if inclusive and arg.zero?
      byte_size = Reline::Unicode.get_next_mbchar_size(current_line, @byte_pointer)
      if byte_size > 0
        @byte_pointer += byte_size
      end
    end
    vi_end_word(key, arg: arg) if arg > 0
  end

  private def vi_next_big_word(key, arg: 1)
    if current_line.bytesize > @byte_pointer
      byte_size, _ = Reline::Unicode.vi_big_forward_word(current_line, @byte_pointer)
      @byte_pointer += byte_size
    end
    arg -= 1
    vi_next_big_word(key, arg: arg) if arg > 0
  end

  private def vi_prev_big_word(key, arg: 1)
    if @byte_pointer > 0
      byte_size, _ = Reline::Unicode.vi_big_backward_word(current_line, @byte_pointer)
      @byte_pointer -= byte_size
    end
    arg -= 1
    vi_prev_big_word(key, arg: arg) if arg > 0
  end

  private def vi_end_big_word(key, arg: 1, inclusive: false)
    if current_line.bytesize > @byte_pointer
      byte_size, _ = Reline::Unicode.vi_big_forward_end_word(current_line, @byte_pointer)
      @byte_pointer += byte_size
    end
    arg -= 1
    if inclusive and arg.zero?
      byte_size = Reline::Unicode.get_next_mbchar_size(current_line, @byte_pointer)
      if byte_size > 0
        @byte_pointer += byte_size
      end
    end
    vi_end_big_word(key, arg: arg) if arg > 0
  end

  private def vi_delete_prev_char(key)
    if @byte_pointer == 0 and @line_index > 0
      @byte_pointer = @buffer_of_lines[@line_index - 1].bytesize
      @buffer_of_lines[@line_index - 1] += @buffer_of_lines.delete_at(@line_index)
      @line_index -= 1
      process_auto_indent cursor_dependent: false
    elsif @byte_pointer > 0
      byte_size = Reline::Unicode.get_prev_mbchar_size(current_line, @byte_pointer)
      @byte_pointer -= byte_size
      line, _ = byteslice!(current_line, @byte_pointer, byte_size)
      set_current_line(line)
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
    deleted = +''
    arg.times do
      if @byte_pointer > 0
        byte_size = Reline::Unicode.get_prev_mbchar_size(current_line, @byte_pointer)
        @byte_pointer -= byte_size
        line, mbchar = byteslice!(current_line, @byte_pointer, byte_size)
        set_current_line(line)
        deleted.prepend(mbchar)
      end
    end
    copy_for_vi(deleted)
  end

  private def vi_change_meta(key, arg: nil)
    if @vi_waiting_operator
      set_current_line('', 0) if @vi_waiting_operator == :vi_change_meta_confirm && arg.nil?
      @vi_waiting_operator = nil
      @vi_waiting_operator_arg = nil
    else
      @drop_terminate_spaces = true
      @vi_waiting_operator = :vi_change_meta_confirm
      @vi_waiting_operator_arg = arg || 1
    end
  end

  private def vi_change_meta_confirm(byte_pointer_diff)
    vi_delete_meta_confirm(byte_pointer_diff)
    @config.editing_mode = :vi_insert
    @drop_terminate_spaces = false
  end

  private def vi_delete_meta(key, arg: nil)
    if @vi_waiting_operator
      set_current_line('', 0) if @vi_waiting_operator == :vi_delete_meta_confirm && arg.nil?
      @vi_waiting_operator = nil
      @vi_waiting_operator_arg = nil
    else
      @vi_waiting_operator = :vi_delete_meta_confirm
      @vi_waiting_operator_arg = arg || 1
    end
  end

  private def vi_delete_meta_confirm(byte_pointer_diff)
    if byte_pointer_diff > 0
      line, cut = byteslice!(current_line, @byte_pointer, byte_pointer_diff)
    elsif byte_pointer_diff < 0
      line, cut = byteslice!(current_line, @byte_pointer + byte_pointer_diff, -byte_pointer_diff)
    else
      return
    end
    copy_for_vi(cut)
    set_current_line(line, @byte_pointer + (byte_pointer_diff < 0 ? byte_pointer_diff : 0))
  end

  private def vi_yank(key, arg: nil)
    if @vi_waiting_operator
      copy_for_vi(current_line) if @vi_waiting_operator == :vi_yank_confirm && arg.nil?
      @vi_waiting_operator = nil
      @vi_waiting_operator_arg = nil
    else
      @vi_waiting_operator = :vi_yank_confirm
      @vi_waiting_operator_arg = arg || 1
    end
  end

  private def vi_yank_confirm(byte_pointer_diff)
    if byte_pointer_diff > 0
      cut = current_line.byteslice(@byte_pointer, byte_pointer_diff)
    elsif byte_pointer_diff < 0
      cut = current_line.byteslice(@byte_pointer + byte_pointer_diff, -byte_pointer_diff)
    else
      return
    end
    copy_for_vi(cut)
  end

  private def vi_list_or_eof(key)
    if buffer_empty?
      @eof = true
      finish
    else
      ed_newline(key)
    end
  end
  alias_method :vi_end_of_transmission, :vi_list_or_eof
  alias_method :vi_eof_maybe, :vi_list_or_eof

  private def ed_delete_next_char(key, arg: 1)
    byte_size = Reline::Unicode.get_next_mbchar_size(current_line, @byte_pointer)
    unless current_line.empty? || byte_size == 0
      line, mbchar = byteslice!(current_line, @byte_pointer, byte_size)
      copy_for_vi(mbchar)
      if @byte_pointer > 0 && current_line.bytesize == @byte_pointer + byte_size
        byte_size = Reline::Unicode.get_prev_mbchar_size(line, @byte_pointer)
        set_current_line(line, @byte_pointer - byte_size)
      else
        set_current_line(line, @byte_pointer)
      end
    end
    arg -= 1
    ed_delete_next_char(key, arg: arg) if arg > 0
  end

  private def vi_to_history_line(key)
    if Reline::HISTORY.empty?
      return
    end
    move_history(0, line: :start, cursor: :start)
  end

  private def vi_histedit(key)
    path = Tempfile.open { |fp|
      fp.write whole_lines.join("\n")
      fp.path
    }
    system("#{ENV['EDITOR']} #{path}")
    @buffer_of_lines = File.read(path).split("\n")
    @buffer_of_lines = [String.new(encoding: @encoding)] if @buffer_of_lines.empty?
    @line_index = 0
    finish
  end

  private def vi_paste_prev(key, arg: 1)
    if @vi_clipboard.size > 0
      cursor_point = @vi_clipboard.grapheme_clusters[0..-2].join
      set_current_line(byteinsert(current_line, @byte_pointer, @vi_clipboard), @byte_pointer + cursor_point.bytesize)
    end
    arg -= 1
    vi_paste_prev(key, arg: arg) if arg > 0
  end

  private def vi_paste_next(key, arg: 1)
    if @vi_clipboard.size > 0
      byte_size = Reline::Unicode.get_next_mbchar_size(current_line, @byte_pointer)
      line = byteinsert(current_line, @byte_pointer + byte_size, @vi_clipboard)
      set_current_line(line, @byte_pointer + @vi_clipboard.bytesize)
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
    # Implementing behavior of vi, not Readline's vi-mode.
    @byte_pointer, = current_line.grapheme_clusters.inject([0, 0]) { |(total_byte_size, total_width), gc|
      mbchar_width = Reline::Unicode.get_mbchar_width(gc)
      break [total_byte_size, total_width] if (total_width + mbchar_width) >= arg
      [total_byte_size + gc.bytesize, total_width + mbchar_width]
    }
  end

  private def vi_replace_char(key, arg: 1)
    @waiting_proc = ->(k) {
      if arg == 1
        byte_size = Reline::Unicode.get_next_mbchar_size(current_line, @byte_pointer)
        before = current_line.byteslice(0, @byte_pointer)
        remaining_point = @byte_pointer + byte_size
        after = current_line.byteslice(remaining_point, current_line.bytesize - remaining_point)
        set_current_line(before + k.chr + after)
        @waiting_proc = nil
      elsif arg > 1
        byte_size = 0
        arg.times do
          byte_size += Reline::Unicode.get_next_mbchar_size(current_line, @byte_pointer + byte_size)
        end
        before = current_line.byteslice(0, @byte_pointer)
        remaining_point = @byte_pointer + byte_size
        after = current_line.byteslice(remaining_point, current_line.bytesize - remaining_point)
        replaced = k.chr * arg
        set_current_line(before + replaced + after, @byte_pointer + replaced.bytesize)
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
    current_line.byteslice(@byte_pointer..-1).grapheme_clusters.each do |mbchar|
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
      byte_size, _ = total
      @byte_pointer += byte_size
    elsif need_prev_char and found and prev_total
      byte_size, _ = prev_total
      @byte_pointer += byte_size
    end
    if inclusive
      byte_size = Reline::Unicode.get_next_mbchar_size(current_line, @byte_pointer)
      if byte_size > 0
        @byte_pointer += byte_size
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
    current_line.byteslice(0..@byte_pointer).grapheme_clusters.reverse_each do |mbchar|
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
      byte_size, _ = total
      @byte_pointer -= byte_size
    elsif need_next_char and found and prev_total
      byte_size, _ = prev_total
      @byte_pointer -= byte_size
    end
    @waiting_proc = nil
  end

  private def vi_join_lines(key, arg: 1)
    if @buffer_of_lines.size > @line_index + 1
      next_line = @buffer_of_lines.delete_at(@line_index + 1).lstrip
      set_current_line(current_line + ' ' + next_line, current_line.bytesize)
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
    @byte_pointer, @line_index = @mark_pointer
    @mark_pointer = new_pointer
  end
  alias_method :exchange_point_and_mark, :em_exchange_mark

  private def emacs_editing_mode(key)
    @config.editing_mode = :emacs
  end

  private def vi_editing_mode(key)
    @config.editing_mode = :vi_insert
  end

  private def undo(_key)
    @undoing = true

    return if @input_lines_position <= 0

    @input_lines_position -= 1
    target_lines, target_cursor_x, target_cursor_y = @input_lines[@input_lines_position]
    set_current_lines(target_lines.dup, target_cursor_x, target_cursor_y)
  end

  private def redo(_key)
    @undoing = true

    return if @input_lines_position >= @input_lines.size - 1

    @input_lines_position += 1
    target_lines, target_cursor_x, target_cursor_y = @input_lines[@input_lines_position]
    set_current_lines(target_lines.dup, target_cursor_x, target_cursor_y)
  end

  private def prev_action_state_value(type)
    @prev_action_state[0] == type ? @prev_action_state[1] : nil
  end

  private def set_next_action_state(type, value)
    @next_action_state = [type, value]
  end

  private def re_read_init_file(_key)
    @config.reload
  end
end
