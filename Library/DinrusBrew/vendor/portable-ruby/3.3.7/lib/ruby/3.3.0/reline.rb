require 'io/console'
require 'forwardable'
require 'reline/version'
require 'reline/config'
require 'reline/key_actor'
require 'reline/key_stroke'
require 'reline/line_editor'
require 'reline/history'
require 'reline/terminfo'
require 'reline/io'
require 'reline/face'
require 'rbconfig'

module Reline
  # NOTE: For making compatible with the rb-readline gem
  FILENAME_COMPLETION_PROC = nil
  USERNAME_COMPLETION_PROC = nil

  class ConfigEncodingConversionError < StandardError; end

  Key = Struct.new(:char, :combined_char, :with_meta) do
    # For dialog_proc `key.match?(dialog.name)`
    def match?(sym)
      combined_char.is_a?(Symbol) && combined_char == sym
    end
  end
  CursorPos = Struct.new(:x, :y)
  DialogRenderInfo = Struct.new(
    :pos,
    :contents,
    :face,
    :bg_color, # For the time being, this line should stay here for the compatibility with IRB.
    :width,
    :height,
    :scrollbar,
    keyword_init: true
  )

  class Core
    ATTR_READER_NAMES = %i(
      completion_append_character
      basic_word_break_characters
      completer_word_break_characters
      basic_quote_characters
      completer_quote_characters
      filename_quote_characters
      special_prefixes
      completion_proc
      output_modifier_proc
      prompt_proc
      auto_indent_proc
      pre_input_hook
      dig_perfect_match_proc
    ).each(&method(:attr_reader))

    attr_accessor :config
    attr_accessor :key_stroke
    attr_accessor :line_editor
    attr_accessor :last_incremental_search
    attr_reader :output

    extend Forwardable
    def_delegators :config,
      :autocompletion,
      :autocompletion=

    def initialize
      self.output = STDOUT
      @mutex = Mutex.new
      @dialog_proc_list = {}
      yield self
      @completion_quote_character = nil
    end

    def io_gate
      Reline::IOGate
    end

    def encoding
      io_gate.encoding
    end

    def completion_append_character=(val)
      if val.nil?
        @completion_append_character = nil
      elsif val.size == 1
        @completion_append_character = val.encode(encoding)
      elsif val.size > 1
        @completion_append_character = val[0].encode(encoding)
      else
        @completion_append_character = nil
      end
    end

    def basic_word_break_characters=(v)
      @basic_word_break_characters = v.encode(encoding)
    end

    def completer_word_break_characters=(v)
      @completer_word_break_characters = v.encode(encoding)
    end

    def basic_quote_characters=(v)
      @basic_quote_characters = v.encode(encoding)
    end

    def completer_quote_characters=(v)
      @completer_quote_characters = v.encode(encoding)
    end

    def filename_quote_characters=(v)
      @filename_quote_characters = v.encode(encoding)
    end

    def special_prefixes=(v)
      @special_prefixes = v.encode(encoding)
    end

    def completion_case_fold=(v)
      @config.completion_ignore_case = v
    end

    def completion_case_fold
      @config.completion_ignore_case
    end

    def completion_quote_character
      @completion_quote_character
    end

    def completion_proc=(p)
      raise ArgumentError unless p.respond_to?(:call) or p.nil?
      @completion_proc = p
    end

    def output_modifier_proc=(p)
      raise ArgumentError unless p.respond_to?(:call) or p.nil?
      @output_modifier_proc = p
    end

    def prompt_proc=(p)
      raise ArgumentError unless p.respond_to?(:call) or p.nil?
      @prompt_proc = p
    end

    def auto_indent_proc=(p)
      raise ArgumentError unless p.respond_to?(:call) or p.nil?
      @auto_indent_proc = p
    end

    def pre_input_hook=(p)
      @pre_input_hook = p
    end

    def dig_perfect_match_proc=(p)
      raise ArgumentError unless p.respond_to?(:call) or p.nil?
      @dig_perfect_match_proc = p
    end

    DialogProc = Struct.new(:dialog_proc, :context)
    def add_dialog_proc(name_sym, p, context = nil)
      raise ArgumentError unless name_sym.instance_of?(Symbol)
      if p.nil?
        @dialog_proc_list.delete(name_sym)
      else
        raise ArgumentError unless p.respond_to?(:call)
        @dialog_proc_list[name_sym] = DialogProc.new(p, context)
      end
    end

    def dialog_proc(name_sym)
      @dialog_proc_list[name_sym]
    end

    def input=(val)
      raise TypeError unless val.respond_to?(:getc) or val.nil?
      if val.respond_to?(:getc) && io_gate.respond_to?(:input=)
        io_gate.input = val
      end
    end

    def output=(val)
      raise TypeError unless val.respond_to?(:write) or val.nil?
      @output = val
      if io_gate.respond_to?(:output=)
        io_gate.output = val
      end
    end

    def vi_editing_mode
      config.editing_mode = :vi_insert
      nil
    end

    def emacs_editing_mode
      config.editing_mode = :emacs
      nil
    end

    def vi_editing_mode?
      config.editing_mode_is?(:vi_insert, :vi_command)
    end

    def emacs_editing_mode?
      config.editing_mode_is?(:emacs)
    end

    def get_screen_size
      io_gate.get_screen_size
    end

    Reline::DEFAULT_DIALOG_PROC_AUTOCOMPLETE = ->() {
      # autocomplete
      return unless config.autocompletion

      journey_data = completion_journey_data
      return unless journey_data

      target = journey_data.list.first
      completed = journey_data.list[journey_data.pointer]
      result = journey_data.list.drop(1)
      pointer = journey_data.pointer - 1
      return if completed.empty? || (result == [completed] && pointer < 0)

      target_width = Reline::Unicode.calculate_width(target)
      completed_width = Reline::Unicode.calculate_width(completed)
      if cursor_pos.x <= completed_width - target_width
        # When target is rendered on the line above cursor position
        x = screen_width - completed_width
        y = -1
      else
        x = [cursor_pos.x - completed_width, 0].max
        y = 0
      end
      cursor_pos_to_render = Reline::CursorPos.new(x, y)
      if context and context.is_a?(Array)
        context.clear
        context.push(cursor_pos_to_render, result, pointer, dialog)
      end
      dialog.pointer = pointer
      DialogRenderInfo.new(
        pos: cursor_pos_to_render,
        contents: result,
        scrollbar: true,
        height: [15, preferred_dialog_height].min,
        face: :completion_dialog
      )
    }
    Reline::DEFAULT_DIALOG_CONTEXT = Array.new

    def readmultiline(prompt = '', add_hist = false, &confirm_multiline_termination)
      @mutex.synchronize do
        unless confirm_multiline_termination
          raise ArgumentError.new('#readmultiline needs block to confirm multiline termination')
        end

        io_gate.with_raw_input do
          inner_readline(prompt, add_hist, true, &confirm_multiline_termination)
        end

        whole_buffer = line_editor.whole_buffer.dup
        whole_buffer.taint if RUBY_VERSION < '2.7'
        if add_hist and whole_buffer and whole_buffer.chomp("\n").size > 0
          Reline::HISTORY << whole_buffer
        end

        if line_editor.eof?
          line_editor.reset_line
          # Return nil if the input is aborted by C-d.
          nil
        else
          whole_buffer
        end
      end
    end

    def readline(prompt = '', add_hist = false)
      @mutex.synchronize do
        io_gate.with_raw_input do
          inner_readline(prompt, add_hist, false)
        end

        line = line_editor.line.dup
        line.taint if RUBY_VERSION < '2.7'
        if add_hist and line and line.chomp("\n").size > 0
          Reline::HISTORY << line.chomp("\n")
        end

        line_editor.reset_line if line_editor.line.nil?
        line
      end
    end

    private def inner_readline(prompt, add_hist, multiline, &confirm_multiline_termination)
      if ENV['RELINE_STDERR_TTY']
        if io_gate.win?
          $stderr = File.open(ENV['RELINE_STDERR_TTY'], 'a')
        else
          $stderr.reopen(ENV['RELINE_STDERR_TTY'], 'w')
        end
        $stderr.sync = true
        $stderr.puts "Reline is used by #{Process.pid}"
      end
      unless config.test_mode or config.loaded?
        config.read
        io_gate.set_default_key_bindings(config)
      end
      otio = io_gate.prep

      may_req_ambiguous_char_width
      line_editor.reset(prompt, encoding: encoding)
      if multiline
        line_editor.multiline_on
        if block_given?
          line_editor.confirm_multiline_termination_proc = confirm_multiline_termination
        end
      else
        line_editor.multiline_off
      end
      line_editor.output = output
      line_editor.completion_proc = completion_proc
      line_editor.completion_append_character = completion_append_character
      line_editor.output_modifier_proc = output_modifier_proc
      line_editor.prompt_proc = prompt_proc
      line_editor.auto_indent_proc = auto_indent_proc
      line_editor.dig_perfect_match_proc = dig_perfect_match_proc

      # Readline calls pre_input_hook just after printing the first prompt.
      line_editor.print_nomultiline_prompt
      pre_input_hook&.call

      unless Reline::IOGate.dumb?
        @dialog_proc_list.each_pair do |name_sym, d|
          line_editor.add_dialog_proc(name_sym, d.dialog_proc, d.context)
        end
      end

      line_editor.update_dialogs
      line_editor.rerender

      begin
        line_editor.set_signal_handlers
        loop do
          read_io(config.keyseq_timeout) { |inputs|
            line_editor.set_pasting_state(io_gate.in_pasting?)
            inputs.each do |key|
              if key.char == :bracketed_paste_start
                text = io_gate.read_bracketed_paste
                line_editor.insert_multiline_text(text)
                line_editor.scroll_into_view
              else
                line_editor.update(key)
              end
            end
          }
          if line_editor.finished?
            line_editor.render_finished
            break
          else
            line_editor.set_pasting_state(io_gate.in_pasting?)
            line_editor.rerender
          end
        end
        io_gate.move_cursor_column(0)
      rescue Errno::EIO
        # Maybe the I/O has been closed.
      ensure
        line_editor.finalize
        io_gate.deprep(otio)
      end
    end

    # GNU Readline watis for "keyseq-timeout" milliseconds when the input is
    # ambiguous whether it is matching or matched.
    # If the next character does not arrive within the specified timeout, input
    # is considered as matched.
    # `ESC` is ambiguous because it can be a standalone ESC (matched) or part of
    # `ESC char` or part of CSI sequence (matching).
    private def read_io(keyseq_timeout, &block)
      buffer = []
      status = KeyStroke::MATCHING
      loop do
        timeout = status == KeyStroke::MATCHING_MATCHED ? keyseq_timeout.fdiv(1000) : Float::INFINITY
        c = io_gate.getc(timeout)
        if c.nil? || c == -1
          if status == KeyStroke::MATCHING_MATCHED
            status = KeyStroke::MATCHED
          elsif buffer.empty?
            # io_gate is closed and reached EOF
            block.call([Key.new(nil, nil, false)])
            return
          else
            status = KeyStroke::UNMATCHED
          end
        else
          buffer << c
          status = key_stroke.match_status(buffer)
        end

        if status == KeyStroke::MATCHED || status == KeyStroke::UNMATCHED
          expanded, rest_bytes = key_stroke.expand(buffer)
          rest_bytes.reverse_each { |c| io_gate.ungetc(c) }
          block.call(expanded)
          return
        end
      end
    end

    def ambiguous_width
      may_req_ambiguous_char_width unless defined? @ambiguous_width
      @ambiguous_width
    end

    private def may_req_ambiguous_char_width
      @ambiguous_width = 2 if io_gate.dumb? || !STDIN.tty? || !STDOUT.tty?
      return if defined? @ambiguous_width
      io_gate.move_cursor_column(0)
      begin
        output.write "\u{25bd}"
      rescue Encoding::UndefinedConversionError
        # LANG=C
        @ambiguous_width = 1
      else
        @ambiguous_width = io_gate.cursor_pos.x
      end
      io_gate.move_cursor_column(0)
      io_gate.erase_after_cursor
    end
  end

  extend Forwardable
  extend SingleForwardable

  #--------------------------------------------------------
  # Documented API
  #--------------------------------------------------------

  (Core::ATTR_READER_NAMES).each { |name|
    def_single_delegators :core, :"#{name}", :"#{name}="
  }
  def_single_delegators :core, :input=, :output=
  def_single_delegators :core, :vi_editing_mode, :emacs_editing_mode
  def_single_delegators :core, :readline
  def_single_delegators :core, :completion_case_fold, :completion_case_fold=
  def_single_delegators :core, :completion_quote_character
  def_instance_delegators self, :readline
  private :readline


  #--------------------------------------------------------
  # Undocumented API
  #--------------------------------------------------------

  # Testable in original
  def_single_delegators :core, :get_screen_size
  def_single_delegators :line_editor, :eof?
  def_instance_delegators self, :eof?
  def_single_delegators :line_editor, :delete_text
  def_single_delegator :line_editor, :line, :line_buffer
  def_single_delegator :line_editor, :byte_pointer, :point
  def_single_delegator :line_editor, :byte_pointer=, :point=

  def self.insert_text(text)
    line_editor.insert_multiline_text(text)
    self
  end

  # Untestable in original
  def_single_delegator :line_editor, :rerender, :redisplay
  def_single_delegators :core, :vi_editing_mode?, :emacs_editing_mode?
  def_single_delegators :core, :ambiguous_width
  def_single_delegators :core, :last_incremental_search
  def_single_delegators :core, :last_incremental_search=
  def_single_delegators :core, :add_dialog_proc
  def_single_delegators :core, :dialog_proc
  def_single_delegators :core, :autocompletion, :autocompletion=

  def_single_delegators :core, :readmultiline
  def_instance_delegators self, :readmultiline
  private :readmultiline

  def self.encoding_system_needs
    self.core.encoding
  end

  def self.core
    @core ||= Core.new { |core|
      core.config = Reline::Config.new
      core.key_stroke = Reline::KeyStroke.new(core.config)
      core.line_editor = Reline::LineEditor.new(core.config, core.encoding)

      core.basic_word_break_characters = " \t\n`><=;|&{("
      core.completer_word_break_characters = " \t\n`><=;|&{("
      core.basic_quote_characters = '"\''
      core.completer_quote_characters = '"\''
      core.filename_quote_characters = ""
      core.special_prefixes = ""
      core.add_dialog_proc(:autocomplete, Reline::DEFAULT_DIALOG_PROC_AUTOCOMPLETE, Reline::DEFAULT_DIALOG_CONTEXT)
    }
  end

  def self.ungetc(c)
    core.io_gate.ungetc(c)
  end

  def self.line_editor
    core.line_editor
  end
end


Reline::IOGate = Reline::IO.decide_io_gate

# Deprecated
Reline::GeneralIO = Reline::Dumb.new

Reline::Face.load_initial_configs

Reline::HISTORY = Reline::History.new(Reline.core.config)
