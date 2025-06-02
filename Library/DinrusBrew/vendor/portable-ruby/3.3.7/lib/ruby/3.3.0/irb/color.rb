# frozen_string_literal: true
require 'reline'
require 'ripper'
require_relative 'ruby-lex'

module IRB # :nodoc:
  module Color
    CLEAR     = 0
    BOLD      = 1
    UNDERLINE = 4
    REVERSE   = 7
    BLACK     = 30
    RED       = 31
    GREEN     = 32
    YELLOW    = 33
    BLUE      = 34
    MAGENTA   = 35
    CYAN      = 36
    WHITE     = 37

    TOKEN_KEYWORDS = {
      on_kw: ['nil', 'self', 'true', 'false', '__FILE__', '__LINE__', '__ENCODING__'],
      on_const: ['ENV'],
    }
    private_constant :TOKEN_KEYWORDS

    # A constant of all-bit 1 to match any Ripper's state in #dispatch_seq
    ALL = -1
    private_constant :ALL

    begin
      # Following pry's colors where possible, but sometimes having a compromise like making
      # backtick and regexp as red (string's color, because they're sharing tokens).
      TOKEN_SEQ_EXPRS = {
        on_CHAR:            [[BLUE, BOLD],            ALL],
        on_backtick:        [[RED, BOLD],             ALL],
        on_comment:         [[BLUE, BOLD],            ALL],
        on_const:           [[BLUE, BOLD, UNDERLINE], ALL],
        on_embexpr_beg:     [[RED],                   ALL],
        on_embexpr_end:     [[RED],                   ALL],
        on_embvar:          [[RED],                   ALL],
        on_float:           [[MAGENTA, BOLD],         ALL],
        on_gvar:            [[GREEN, BOLD],           ALL],
        on_heredoc_beg:     [[RED],                   ALL],
        on_heredoc_end:     [[RED],                   ALL],
        on_ident:           [[BLUE, BOLD],            Ripper::EXPR_ENDFN],
        on_imaginary:       [[BLUE, BOLD],            ALL],
        on_int:             [[BLUE, BOLD],            ALL],
        on_kw:              [[GREEN],                 ALL],
        on_label:           [[MAGENTA],               ALL],
        on_label_end:       [[RED, BOLD],             ALL],
        on_qsymbols_beg:    [[RED, BOLD],             ALL],
        on_qwords_beg:      [[RED, BOLD],             ALL],
        on_rational:        [[BLUE, BOLD],            ALL],
        on_regexp_beg:      [[RED, BOLD],             ALL],
        on_regexp_end:      [[RED, BOLD],             ALL],
        on_symbeg:          [[YELLOW],                ALL],
        on_symbols_beg:     [[RED, BOLD],             ALL],
        on_tstring_beg:     [[RED, BOLD],             ALL],
        on_tstring_content: [[RED],                   ALL],
        on_tstring_end:     [[RED, BOLD],             ALL],
        on_words_beg:       [[RED, BOLD],             ALL],
        on_parse_error:     [[RED, REVERSE],          ALL],
        compile_error:      [[RED, REVERSE],          ALL],
        on_assign_error:    [[RED, REVERSE],          ALL],
        on_alias_error:     [[RED, REVERSE],          ALL],
        on_class_name_error:[[RED, REVERSE],          ALL],
        on_param_error:     [[RED, REVERSE],          ALL],
        on___end__:         [[GREEN],                 ALL],
      }
    rescue NameError
      # Give up highlighting Ripper-incompatible older Ruby
      TOKEN_SEQ_EXPRS = {}
    end
    private_constant :TOKEN_SEQ_EXPRS

    ERROR_TOKENS = TOKEN_SEQ_EXPRS.keys.select { |k| k.to_s.end_with?('error') }
    private_constant :ERROR_TOKENS

    class << self
      def colorable?
        supported = $stdout.tty? && (/mswin|mingw/.match?(RUBY_PLATFORM) || (ENV.key?('TERM') && ENV['TERM'] != 'dumb'))

        # because ruby/debug also uses irb's color module selectively,
        # irb won't be activated in that case.
        if IRB.respond_to?(:conf)
          supported && !!IRB.conf.fetch(:USE_COLORIZE, true)
        else
          supported
        end
      end

      def inspect_colorable?(obj, seen: {}.compare_by_identity)
        case obj
        when String, Symbol, Regexp, Integer, Float, FalseClass, TrueClass, NilClass
          true
        when Hash
          without_circular_ref(obj, seen: seen) do
            obj.all? { |k, v| inspect_colorable?(k, seen: seen) && inspect_colorable?(v, seen: seen) }
          end
        when Array
          without_circular_ref(obj, seen: seen) do
            obj.all? { |o| inspect_colorable?(o, seen: seen) }
          end
        when Range
          inspect_colorable?(obj.begin, seen: seen) && inspect_colorable?(obj.end, seen: seen)
        when Module
          !obj.name.nil?
        else
          false
        end
      end

      def clear(colorable: colorable?)
        return '' unless colorable
        "\e[#{CLEAR}m"
      end

      def colorize(text, seq, colorable: colorable?)
        return text unless colorable
        seq = seq.map { |s| "\e[#{const_get(s)}m" }.join('')
        "#{seq}#{text}#{clear(colorable: colorable)}"
      end

      # If `complete` is false (code is incomplete), this does not warn compile_error.
      # This option is needed to avoid warning a user when the compile_error is happening
      # because the input is not wrong but just incomplete.
      def colorize_code(code, complete: true, ignore_error: false, colorable: colorable?, local_variables: [])
        return code unless colorable

        symbol_state = SymbolState.new
        colored = +''
        lvars_code = RubyLex.generate_local_variables_assign_code(local_variables)
        code_with_lvars = lvars_code ? "#{lvars_code}\n#{code}" : code

        scan(code_with_lvars, allow_last_error: !complete) do |token, str, expr|
          # handle uncolorable code
          if token.nil?
            colored << Reline::Unicode.escape_for_print(str)
            next
          end

          # IRB::ColorPrinter skips colorizing fragments with any invalid token
          if ignore_error && ERROR_TOKENS.include?(token)
            return Reline::Unicode.escape_for_print(code)
          end

          in_symbol = symbol_state.scan_token(token)
          str.each_line do |line|
            line = Reline::Unicode.escape_for_print(line)
            if seq = dispatch_seq(token, expr, line, in_symbol: in_symbol)
              colored << seq.map { |s| "\e[#{s}m" }.join('')
              colored << line.sub(/\Z/, clear(colorable: colorable))
            else
              colored << line
            end
          end
        end

        if lvars_code
          raise "#{lvars_code.dump} should have no \\n" if lvars_code.include?("\n")
          colored.sub!(/\A.+\n/, '') # delete_prefix lvars_code with colors
        end
        colored
      end

      private

      def without_circular_ref(obj, seen:, &block)
        return false if seen.key?(obj)
        seen[obj] = true
        block.call
      ensure
        seen.delete(obj)
      end

      def scan(code, allow_last_error:)
        verbose, $VERBOSE = $VERBOSE, nil
        RubyLex.compile_with_errors_suppressed(code) do |inner_code, line_no|
          lexer = Ripper::Lexer.new(inner_code, '(ripper)', line_no)
          byte_pos = 0
          line_positions = [0]
          inner_code.lines.each do |line|
            line_positions << line_positions.last + line.bytesize
          end

          on_scan = proc do |elem|
            start_pos = line_positions[elem.pos[0] - 1] + elem.pos[1]

            # yield uncolorable code
            if byte_pos < start_pos
              yield(nil, inner_code.byteslice(byte_pos...start_pos), nil)
            end

            if byte_pos <= start_pos
              str = elem.tok
              yield(elem.event, str, elem.state)
              byte_pos = start_pos + str.bytesize
            end
          end

          lexer.scan.each do |elem|
            next if allow_last_error and /meets end of file|unexpected end-of-input/ =~ elem.message
            on_scan.call(elem)
          end
          # yield uncolorable DATA section
          yield(nil, inner_code.byteslice(byte_pos...inner_code.bytesize), nil) if byte_pos < inner_code.bytesize
        end
      ensure
        $VERBOSE = verbose
      end

      def dispatch_seq(token, expr, str, in_symbol:)
        if ERROR_TOKENS.include?(token)
          TOKEN_SEQ_EXPRS[token][0]
        elsif in_symbol
          [YELLOW]
        elsif TOKEN_KEYWORDS.fetch(token, []).include?(str)
          [CYAN, BOLD]
        elsif (seq, exprs = TOKEN_SEQ_EXPRS[token]; (expr & (exprs || 0)) != 0)
          seq
        else
          nil
        end
      end
    end

    # A class to manage a state to know whether the current token is for Symbol or not.
    class SymbolState
      def initialize
        # Push `true` to detect Symbol. `false` to increase the nest level for non-Symbol.
        @stack = []
      end

      # Return true if the token is a part of Symbol.
      def scan_token(token)
        prev_state = @stack.last
        case token
        when :on_symbeg, :on_symbols_beg, :on_qsymbols_beg
          @stack << true
        when :on_ident, :on_op, :on_const, :on_ivar, :on_cvar, :on_gvar, :on_kw, :on_backtick
          if @stack.last # Pop only when it's Symbol
            @stack.pop
            return prev_state
          end
        when :on_tstring_beg
          @stack << false
        when :on_embexpr_beg
          @stack << false
          return prev_state
        when :on_tstring_end # :on_tstring_end may close Symbol
          @stack.pop
          return prev_state
        when :on_embexpr_end
          @stack.pop
        end
        @stack.last
      end
    end
    private_constant :SymbolState
  end
end
