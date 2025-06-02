# frozen_string_literal: true
#
#   irb/input-method.rb - input methods used irb
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#

require_relative 'completion'
require_relative "history"
require 'io/console'
require 'reline'

module IRB
  class InputMethod
    BASIC_WORD_BREAK_CHARACTERS = " \t\n`><=;|&{("

    # The irb prompt associated with this input method
    attr_accessor :prompt

    # Reads the next line from this input method.
    #
    # See IO#gets for more information.
    def gets
      fail NotImplementedError
    end
    public :gets

    def winsize
      if instance_variable_defined?(:@stdout) && @stdout.tty?
        @stdout.winsize
      else
        [24, 80]
      end
    end

    # Whether this input method is still readable when there is no more data to
    # read.
    #
    # See IO#eof for more information.
    def readable_after_eof?
      false
    end

    def support_history_saving?
      false
    end

    def prompting?
      false
    end

    # For debug message
    def inspect
      'Abstract InputMethod'
    end
  end

  class StdioInputMethod < InputMethod
    # Creates a new input method object
    def initialize
      @line_no = 0
      @line = []
      @stdin = IO.open(STDIN.to_i, :external_encoding => IRB.conf[:LC_MESSAGES].encoding, :internal_encoding => "-")
      @stdout = IO.open(STDOUT.to_i, 'w', :external_encoding => IRB.conf[:LC_MESSAGES].encoding, :internal_encoding => "-")
    end

    # Reads the next line from this input method.
    #
    # See IO#gets for more information.
    def gets
      puts if @stdout.tty? # workaround for debug compatibility test
      print @prompt
      line = @stdin.gets
      @line[@line_no += 1] = line
    end

    # Whether the end of this input method has been reached, returns +true+ if
    # there is no more data to read.
    #
    # See IO#eof? for more information.
    def eof?
      if @stdin.wait_readable(0.00001)
        c = @stdin.getc
        result = c.nil? ? true : false
        @stdin.ungetc(c) unless c.nil?
        result
      else # buffer is empty
        false
      end
    end

    # Whether this input method is still readable when there is no more data to
    # read.
    #
    # See IO#eof for more information.
    def readable_after_eof?
      true
    end

    def prompting?
      STDIN.tty?
    end

    # Returns the current line number for #io.
    #
    # #line counts the number of times #gets is called.
    #
    # See IO#lineno for more information.
    def line(line_no)
      @line[line_no]
    end

    # The external encoding for standard input.
    def encoding
      @stdin.external_encoding
    end

    # For debug message
    def inspect
      'StdioInputMethod'
    end
  end

  # Use a File for IO with irb, see InputMethod
  class FileInputMethod < InputMethod
    class << self
      def open(file, &block)
        begin
          io = new(file)
          block.call(io)
        ensure
          io&.close
        end
      end
    end

    # Creates a new input method object
    def initialize(file)
      @io = file.is_a?(IO) ? file : File.open(file)
      @external_encoding = @io.external_encoding
    end

    # Whether the end of this input method has been reached, returns +true+ if
    # there is no more data to read.
    #
    # See IO#eof? for more information.
    def eof?
      @io.closed? || @io.eof?
    end

    # Reads the next line from this input method.
    #
    # See IO#gets for more information.
    def gets
      print @prompt
      @io.gets
    end

    # The external encoding for standard input.
    def encoding
      @external_encoding
    end

    # For debug message
    def inspect
      'FileInputMethod'
    end

    def close
      @io.close
    end
  end

  class ReadlineInputMethod < StdioInputMethod
    def self.initialize_readline
      require "readline"
    rescue LoadError
    else
      include ::Readline
    end

    include HistorySavingAbility

    # Creates a new input method object using Readline
    def initialize
      self.class.initialize_readline
      if Readline.respond_to?(:encoding_system_needs)
        IRB.__send__(:set_encoding, Readline.encoding_system_needs.name, override: false)
      end

      super

      @eof = false
      @completor = RegexpCompletor.new

      if Readline.respond_to?("basic_word_break_characters=")
        Readline.basic_word_break_characters = BASIC_WORD_BREAK_CHARACTERS
      end
      Readline.completion_append_character = nil
      Readline.completion_proc = ->(target) {
        bind = IRB.conf[:MAIN_CONTEXT].workspace.binding
        @completor.completion_candidates('', target, '', bind: bind)
      }
    end

    def completion_info
      'RegexpCompletor'
    end

    # Reads the next line from this input method.
    #
    # See IO#gets for more information.
    def gets
      Readline.input = @stdin
      Readline.output = @stdout
      if l = readline(@prompt, false)
        HISTORY.push(l) if !l.empty?
        @line[@line_no += 1] = l + "\n"
      else
        @eof = true
        l
      end
    end

    # Whether the end of this input method has been reached, returns +true+
    # if there is no more data to read.
    #
    # See IO#eof? for more information.
    def eof?
      @eof
    end

    def prompting?
      true
    end

    # For debug message
    def inspect
      readline_impl = (defined?(Reline) && Readline == Reline) ? 'Reline' : 'ext/readline'
      str = "ReadlineInputMethod with #{readline_impl} #{Readline::VERSION}"
      inputrc_path = File.expand_path(ENV['INPUTRC'] || '~/.inputrc')
      str += " and #{inputrc_path}" if File.exist?(inputrc_path)
      str
    end
  end

  class RelineInputMethod < StdioInputMethod
    HISTORY = Reline::HISTORY
    include HistorySavingAbility
    # Creates a new input method object using Reline
    def initialize(completor)
      IRB.__send__(:set_encoding, Reline.encoding_system_needs.name, override: false)

      super()

      @eof = false
      @completor = completor

      Reline.basic_word_break_characters = BASIC_WORD_BREAK_CHARACTERS
      Reline.completion_append_character = nil
      Reline.completer_quote_characters = ''
      Reline.completion_proc = ->(target, preposing, postposing) {
        bind = IRB.conf[:MAIN_CONTEXT].workspace.binding
        @completion_params = [preposing, target, postposing, bind]
        @completor.completion_candidates(preposing, target, postposing, bind: bind)
      }
      Reline.output_modifier_proc =
        if IRB.conf[:USE_COLORIZE]
          proc do |output, complete: |
            next unless IRB::Color.colorable?
            lvars = IRB.CurrentContext&.local_variables || []
            IRB::Color.colorize_code(output, complete: complete, local_variables: lvars)
          end
        else
          proc do |output|
            Reline::Unicode.escape_for_print(output)
          end
        end
      Reline.dig_perfect_match_proc = ->(matched) { display_document(matched) }
      Reline.autocompletion = IRB.conf[:USE_AUTOCOMPLETE]

      if IRB.conf[:USE_AUTOCOMPLETE]
        begin
          require 'rdoc'
          Reline.add_dialog_proc(:show_doc, show_doc_dialog_proc, Reline::DEFAULT_DIALOG_CONTEXT)
        rescue LoadError
        end
      end
    end

    def completion_info
      autocomplete_message = Reline.autocompletion ? 'Autocomplete' : 'Tab Complete'
      "#{autocomplete_message}, #{@completor.inspect}"
    end

    def check_termination(&block)
      @check_termination_proc = block
    end

    def dynamic_prompt(&block)
      @prompt_proc = block
    end

    def auto_indent(&block)
      @auto_indent_proc = block
    end

    def retrieve_doc_namespace(matched)
      preposing, _target, postposing, bind = @completion_params
      @completor.doc_namespace(preposing, matched, postposing, bind: bind)
    end

    def rdoc_ri_driver
      return @rdoc_ri_driver if defined?(@rdoc_ri_driver)

      begin
        require 'rdoc'
      rescue LoadError
        @rdoc_ri_driver = nil
      else
        options = {}
        options[:extra_doc_dirs] = IRB.conf[:EXTRA_DOC_DIRS] unless IRB.conf[:EXTRA_DOC_DIRS].empty?
        @rdoc_ri_driver = RDoc::RI::Driver.new(options)
      end
    end

    def show_doc_dialog_proc
      input_method = self # self is changed in the lambda below.
      ->() {
        dialog.trap_key = nil
        alt_d = [
          [Reline::Key.new(nil, 0xE4, true)], # Normal Alt+d.
          [27, 100], # Normal Alt+d when convert-meta isn't used.
          [195, 164], # The "ä" that appears when Alt+d is pressed on xterm.
          [226, 136, 130] # The "∂" that appears when Alt+d in pressed on iTerm2.
        ]

        if just_cursor_moving and completion_journey_data.nil?
          return nil
        end
        cursor_pos_to_render, result, pointer, autocomplete_dialog = context.pop(4)
        return nil if result.nil? or pointer.nil? or pointer < 0

        name = input_method.retrieve_doc_namespace(result[pointer])
        # Use first one because document dialog does not support multiple namespaces.
        name = name.first if name.is_a?(Array)

        show_easter_egg = name&.match?(/\ARubyVM/) && !ENV['RUBY_YES_I_AM_NOT_A_NORMAL_USER']

        driver = input_method.rdoc_ri_driver

        if key.match?(dialog.name)
          if show_easter_egg
            IRB.__send__(:easter_egg)
          else
            begin
              driver.display_names([name])
            rescue RDoc::RI::Driver::NotFoundError
            end
          end
        end

        begin
          name = driver.expand_name(name)
        rescue RDoc::RI::Driver::NotFoundError
          return nil
        rescue
          return nil # unknown error
        end
        doc = nil
        used_for_class = false
        if not name =~ /#|\./
          found, klasses, includes, extends = driver.classes_and_includes_and_extends_for(name)
          if not found.empty?
            doc = driver.class_document(name, found, klasses, includes, extends)
            used_for_class = true
          end
        end
        unless used_for_class
          doc = RDoc::Markup::Document.new
          begin
            driver.add_method(doc, name)
          rescue RDoc::RI::Driver::NotFoundError
            doc = nil
          rescue
            return nil # unknown error
          end
        end
        return nil if doc.nil?
        width = 40

        right_x = cursor_pos_to_render.x + autocomplete_dialog.width
        if right_x + width > screen_width
          right_width = screen_width - (right_x + 1)
          left_x = autocomplete_dialog.column - width
          left_x = 0 if left_x < 0
          left_width = width > autocomplete_dialog.column ? autocomplete_dialog.column : width
          if right_width.positive? and left_width.positive?
            if right_width >= left_width
              width = right_width
              x = right_x
            else
              width = left_width
              x = left_x
            end
          elsif right_width.positive? and left_width <= 0
            width = right_width
            x = right_x
          elsif right_width <= 0 and left_width.positive?
            width = left_width
            x = left_x
          else # Both are negative width.
            return nil
          end
        else
          x = right_x
        end
        formatter = RDoc::Markup::ToAnsi.new
        formatter.width = width
        dialog.trap_key = alt_d
        mod_key = RUBY_PLATFORM.match?(/darwin/) ? "Option" : "Alt"
        if show_easter_egg
          type = STDOUT.external_encoding == Encoding::UTF_8 ? :unicode : :ascii
          contents = IRB.send(:easter_egg_logo, type).split("\n")
          message = "Press #{mod_key}+d to see more"
          contents[0][0, message.size] = message
        else
          message = "Press #{mod_key}+d to read the full document"
          contents = [message] + doc.accept(formatter).split("\n")
        end
        contents = contents.take(preferred_dialog_height)

        y = cursor_pos_to_render.y
        Reline::DialogRenderInfo.new(pos: Reline::CursorPos.new(x, y), contents: contents, width: width, bg_color: '49')
      }
    end

    def display_document(matched)
      driver = rdoc_ri_driver
      return unless driver

      if matched =~ /\A(?:::)?RubyVM/ and not ENV['RUBY_YES_I_AM_NOT_A_NORMAL_USER']
        IRB.__send__(:easter_egg)
        return
      end

      namespace = retrieve_doc_namespace(matched)
      return unless namespace

      if namespace.is_a?(Array)
        out = RDoc::Markup::Document.new
        namespace.each do |m|
          begin
            driver.add_method(out, m)
          rescue RDoc::RI::Driver::NotFoundError
          end
        end
        driver.display(out)
      else
        begin
          driver.display_names([namespace])
        rescue RDoc::RI::Driver::NotFoundError
        end
      end
    end

    # Reads the next line from this input method.
    #
    # See IO#gets for more information.
    def gets
      Reline.input = @stdin
      Reline.output = @stdout
      Reline.prompt_proc = @prompt_proc
      Reline.auto_indent_proc = @auto_indent_proc if @auto_indent_proc
      if l = Reline.readmultiline(@prompt, false, &@check_termination_proc)
        Reline::HISTORY.push(l) if !l.empty?
        @line[@line_no += 1] = l + "\n"
      else
        @eof = true
        l
      end
    end

    # Whether the end of this input method has been reached, returns +true+
    # if there is no more data to read.
    #
    # See IO#eof? for more information.
    def eof?
      @eof
    end

    def prompting?
      true
    end

    # For debug message
    def inspect
      config = Reline::Config.new
      str = "RelineInputMethod with Reline #{Reline::VERSION}"
      inputrc_path = File.expand_path(config.inputrc_path)
      str += " and #{inputrc_path}" if File.exist?(inputrc_path)
      str
    end
  end

  class ReidlineInputMethod < RelineInputMethod
    def initialize
      warn <<~MSG.strip
        IRB::ReidlineInputMethod is deprecated, please use IRB::RelineInputMethod instead.
      MSG
      super
    end
  end
end
