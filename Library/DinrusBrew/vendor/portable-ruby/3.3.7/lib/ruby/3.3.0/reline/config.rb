class Reline::Config
  attr_reader :test_mode

  KEYSEQ_PATTERN = /\\(?:C|Control)-[A-Za-z_]|\\(?:M|Meta)-[0-9A-Za-z_]|\\(?:C|Control)-(?:M|Meta)-[A-Za-z_]|\\(?:M|Meta)-(?:C|Control)-[A-Za-z_]|\\e|\\[\\\"\'abdfnrtv]|\\\d{1,3}|\\x\h{1,2}|./

  class InvalidInputrc < RuntimeError
    attr_accessor :file, :lineno
  end

  VARIABLE_NAMES = %w{
    completion-ignore-case
    convert-meta
    disable-completion
    history-size
    keyseq-timeout
    show-all-if-ambiguous
    show-mode-in-prompt
    vi-cmd-mode-string
    vi-ins-mode-string
    emacs-mode-string
    enable-bracketed-paste
    isearch-terminators
  }
  VARIABLE_NAME_SYMBOLS = VARIABLE_NAMES.map { |v| :"#{v.tr(?-, ?_)}" }
  VARIABLE_NAME_SYMBOLS.each do |v|
    attr_accessor v
  end

  attr_accessor :autocompletion

  def initialize
    reset_variables
  end

  def reset
    if editing_mode_is?(:vi_command)
      @editing_mode_label = :vi_insert
    end
    @oneshot_key_bindings.clear
  end

  def reset_variables
    @additional_key_bindings = { # from inputrc
      emacs: Reline::KeyActor::Base.new,
      vi_insert: Reline::KeyActor::Base.new,
      vi_command: Reline::KeyActor::Base.new
    }
    @oneshot_key_bindings = Reline::KeyActor::Base.new
    @editing_mode_label = :emacs
    @keymap_label = :emacs
    @keymap_prefix = []
    @default_key_bindings = {
      emacs: Reline::KeyActor::Base.new(Reline::KeyActor::EMACS_MAPPING),
      vi_insert: Reline::KeyActor::Base.new(Reline::KeyActor::VI_INSERT_MAPPING),
      vi_command: Reline::KeyActor::Base.new(Reline::KeyActor::VI_COMMAND_MAPPING)
    }
    @vi_cmd_mode_string = '(cmd)'
    @vi_ins_mode_string = '(ins)'
    @emacs_mode_string = '@'
    # https://tiswww.case.edu/php/chet/readline/readline.html#IDX25
    @history_size = -1 # unlimited
    @keyseq_timeout = 500
    @test_mode = false
    @autocompletion = false
    @convert_meta = seven_bit_encoding?(Reline::IOGate.encoding)
    @loaded = false
    @enable_bracketed_paste = true
    @show_mode_in_prompt = false
    @default_inputrc_path = nil
  end

  def editing_mode
    @default_key_bindings[@editing_mode_label]
  end

  def editing_mode=(val)
    @editing_mode_label = val
  end

  def editing_mode_is?(*val)
    val.any?(@editing_mode_label)
  end

  def keymap
    @default_key_bindings[@keymap_label]
  end

  def loaded?
    @loaded
  end

  def inputrc_path
    case ENV['INPUTRC']
    when nil, ''
    else
      return File.expand_path(ENV['INPUTRC'])
    end

    # In the XDG Specification, if ~/.config/readline/inputrc exists, then
    # ~/.inputrc should not be read, but for compatibility with GNU Readline,
    # if ~/.inputrc exists, then it is given priority.
    home_rc_path = File.expand_path('~/.inputrc')
    return home_rc_path if File.exist?(home_rc_path)

    case path = ENV['XDG_CONFIG_HOME']
    when nil, ''
    else
      path = File.join(path, 'readline/inputrc')
      return path if File.exist?(path) and path == File.expand_path(path)
    end

    path = File.expand_path('~/.config/readline/inputrc')
    return path if File.exist?(path)

    return home_rc_path
  end

  private def default_inputrc_path
    @default_inputrc_path ||= inputrc_path
  end

  def read(file = nil)
    @loaded = true
    file ||= default_inputrc_path
    begin
      if file.respond_to?(:readlines)
        lines = file.readlines
      else
        lines = File.readlines(file)
      end
    rescue Errno::ENOENT
      return nil
    end

    read_lines(lines, file)
    self
  rescue InvalidInputrc => e
    warn e.message
    nil
  end

  def key_bindings
    # The key bindings for each editing mode will be overwritten by the user-defined ones.
    Reline::KeyActor::Composite.new([@oneshot_key_bindings, @additional_key_bindings[@editing_mode_label], @default_key_bindings[@editing_mode_label]])
  end

  def add_oneshot_key_binding(keystroke, target)
    # IRB sets invalid keystroke [Reline::Key]. We should ignore it.
    return unless keystroke.all? { |c| c.is_a?(Integer) }

    @oneshot_key_bindings.add(keystroke, target)
  end

  def reset_oneshot_key_bindings
    @oneshot_key_bindings.clear
  end

  def add_default_key_binding_by_keymap(keymap, keystroke, target)
    @default_key_bindings[keymap].add(keystroke, target)
  end

  def add_default_key_binding(keystroke, target)
    add_default_key_binding_by_keymap(@keymap_label, keystroke, target)
  end

  def read_lines(lines, file = nil)
    if not lines.empty? and lines.first.encoding != Reline.encoding_system_needs
      begin
        lines = lines.map do |l|
          l.encode(Reline.encoding_system_needs)
        rescue Encoding::UndefinedConversionError
          mes = "The inputrc encoded in #{lines.first.encoding.name} can't be converted to the locale #{Reline.encoding_system_needs.name}."
          raise Reline::ConfigEncodingConversionError.new(mes)
        end
      end
    end
    if_stack = []

    lines.each_with_index do |line, no|
      next if line.match(/\A\s*#/)

      no += 1

      line = line.chomp.lstrip
      if line.start_with?('$')
        handle_directive(line[1..-1], file, no, if_stack)
        next
      end

      next if if_stack.any? { |_no, skip| skip }

      case line
      when /^set +([^ ]+) +(.+)/i
        # value ignores everything after a space, raw_value does not.
        var, value, raw_value = $1.downcase, $2.partition(' ').first, $2
        bind_variable(var, value, raw_value)
        next
      when /\s*("#{KEYSEQ_PATTERN}+")\s*:\s*(.*)\s*$/o
        key, func_name = $1, $2
        func_name = func_name.split.first
        keystroke, func = bind_key(key, func_name)
        next unless keystroke
        @additional_key_bindings[@keymap_label].add(@keymap_prefix + keystroke, func)
      end
    end
    unless if_stack.empty?
      raise InvalidInputrc, "#{file}:#{if_stack.last[0]}: unclosed if"
    end
  end

  def handle_directive(directive, file, no, if_stack)
    directive, args = directive.split(' ')
    case directive
    when 'if'
      condition = false
      case args
      when /^mode=(vi|emacs)$/i
        mode = $1.downcase
        # NOTE: mode=vi means vi-insert mode
        mode = 'vi_insert' if mode == 'vi'
        if @editing_mode_label == mode.to_sym
          condition = true
        end
      when 'term'
      when 'version'
      else # application name
        condition = true if args == 'Ruby'
        condition = true if args == 'Reline'
      end
      if_stack << [no, !condition]
    when 'else'
      if if_stack.empty?
        raise InvalidInputrc, "#{file}:#{no}: unmatched else"
      end
      if_stack.last[1] = !if_stack.last[1]
    when 'endif'
      if if_stack.empty?
        raise InvalidInputrc, "#{file}:#{no}: unmatched endif"
      end
      if_stack.pop
    when 'include'
      read(File.expand_path(args))
    end
  end

  def bind_variable(name, value, raw_value)
    case name
    when 'history-size'
      begin
        @history_size = Integer(value)
      rescue ArgumentError
        @history_size = 500
      end
    when 'isearch-terminators'
      @isearch_terminators = retrieve_string(raw_value)
    when 'editing-mode'
      case value
      when 'emacs'
        @editing_mode_label = :emacs
        @keymap_label = :emacs
        @keymap_prefix = []
      when 'vi'
        @editing_mode_label = :vi_insert
        @keymap_label = :vi_insert
        @keymap_prefix = []
      end
    when 'keymap'
      case value
      when 'emacs', 'emacs-standard'
        @keymap_label = :emacs
        @keymap_prefix = []
      when 'emacs-ctlx'
        @keymap_label = :emacs
        @keymap_prefix = [?\C-x.ord]
      when 'emacs-meta'
        @keymap_label = :emacs
        @keymap_prefix = [?\e.ord]
      when 'vi', 'vi-move', 'vi-command'
        @keymap_label = :vi_command
        @keymap_prefix = []
      when 'vi-insert'
        @keymap_label = :vi_insert
        @keymap_prefix = []
      end
    when 'keyseq-timeout'
      @keyseq_timeout = value.to_i
    when 'show-mode-in-prompt'
      case value
      when 'off'
        @show_mode_in_prompt = false
      when 'on'
        @show_mode_in_prompt = true
      else
        @show_mode_in_prompt = false
      end
    when 'vi-cmd-mode-string'
      @vi_cmd_mode_string = retrieve_string(raw_value)
    when 'vi-ins-mode-string'
      @vi_ins_mode_string = retrieve_string(raw_value)
    when 'emacs-mode-string'
      @emacs_mode_string = retrieve_string(raw_value)
    when *VARIABLE_NAMES then
      variable_name = :"@#{name.tr(?-, ?_)}"
      instance_variable_set(variable_name, value.nil? || value == '1' || value == 'on')
    end
  end

  def retrieve_string(str)
    str = $1 if str =~ /\A"(.*)"\z/
    parse_keyseq(str).map { |c| c.chr(Reline.encoding_system_needs) }.join
  end

  def bind_key(key, func_name)
    if key =~ /\A"(.*)"\z/
      keyseq = parse_keyseq($1)
    else
      keyseq = nil
    end
    if func_name =~ /"(.*)"/
      func = parse_keyseq($1)
    else
      func = func_name.tr(?-, ?_).to_sym # It must be macro.
    end
    [keyseq, func]
  end

  def key_notation_to_code(notation)
    case notation
    when /\\(?:C|Control)-([A-Za-z_])/
      (1 + $1.downcase.ord - ?a.ord)
    when /\\(?:M|Meta)-([0-9A-Za-z_])/
      modified_key = $1
      case $1
      when /[0-9]/
        ?\M-0.bytes.first + (modified_key.ord - ?0.ord)
      when /[A-Z]/
        ?\M-A.bytes.first + (modified_key.ord - ?A.ord)
      when /[a-z]/
        ?\M-a.bytes.first + (modified_key.ord - ?a.ord)
      end
    when /\\(?:C|Control)-(?:M|Meta)-[A-Za-z_]/, /\\(?:M|Meta)-(?:C|Control)-[A-Za-z_]/
    # 129 M-^A
    when /\\(\d{1,3})/ then $1.to_i(8) # octal
    when /\\x(\h{1,2})/ then $1.to_i(16) # hexadecimal
    when "\\e" then ?\e.ord
    when "\\\\" then ?\\.ord
    when "\\\"" then ?".ord
    when "\\'" then ?'.ord
    when "\\a" then ?\a.ord
    when "\\b" then ?\b.ord
    when "\\d" then ?\d.ord
    when "\\f" then ?\f.ord
    when "\\n" then ?\n.ord
    when "\\r" then ?\r.ord
    when "\\t" then ?\t.ord
    when "\\v" then ?\v.ord
    else notation.ord
    end
  end

  def parse_keyseq(str)
    ret = []
    str.scan(KEYSEQ_PATTERN) do
      ret << key_notation_to_code($&)
    end
    ret
  end

  def reload
    reset_variables
    read
  end

  private def seven_bit_encoding?(encoding)
    encoding == Encoding::US_ASCII
  end
end
