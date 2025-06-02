# frozen_string_literal: true
#
#   irb/ruby-lex.rb - ruby lexcal analyzer
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#

require "ripper"
require "jruby" if RUBY_ENGINE == "jruby"
require_relative "nesting_parser"

module IRB
  # :stopdoc:
  class RubyLex
    ASSIGNMENT_NODE_TYPES = [
      # Local, instance, global, class, constant, instance, and index assignment:
      #   "foo = bar",
      #   "@foo = bar",
      #   "$foo = bar",
      #   "@@foo = bar",
      #   "::Foo = bar",
      #   "a::Foo = bar",
      #   "Foo = bar"
      #   "foo.bar = 1"
      #   "foo[1] = bar"
      :assign,

      # Operation assignment:
      #   "foo += bar"
      #   "foo -= bar"
      #   "foo ||= bar"
      #   "foo &&= bar"
      :opassign,

      # Multiple assignment:
      #   "foo, bar = 1, 2
      :massign,
    ]

    class TerminateLineInput < StandardError
      def initialize
        super("Terminate Line Input")
      end
    end

    def self.compile_with_errors_suppressed(code, line_no: 1)
      begin
        result = yield code, line_no
      rescue ArgumentError
        # Ruby can issue an error for the code if there is an
        # incomplete magic comment for encoding in it. Force an
        # expression with a new line before the code in this
        # case to prevent magic comment handling.  To make sure
        # line numbers in the lexed code remain the same,
        # decrease the line number by one.
        code = ";\n#{code}"
        line_no -= 1
        result = yield code, line_no
      end
      result
    end

    ERROR_TOKENS = [
      :on_parse_error,
      :compile_error,
      :on_assign_error,
      :on_alias_error,
      :on_class_name_error,
      :on_param_error
    ]

    def self.generate_local_variables_assign_code(local_variables)
      "#{local_variables.join('=')}=nil;" unless local_variables.empty?
    end

    # Some part of the code is not included in Ripper's token.
    # Example: DATA part, token after heredoc_beg when heredoc has unclosed embexpr.
    # With interpolated tokens, tokens.map(&:tok).join will be equal to code.
    def self.interpolate_ripper_ignored_tokens(code, tokens)
      line_positions = [0]
      code.lines.each do |line|
        line_positions << line_positions.last + line.bytesize
      end
      prev_byte_pos = 0
      interpolated = []
      prev_line = 1
      tokens.each do |t|
        line, col = t.pos
        byte_pos = line_positions[line - 1] + col
        if prev_byte_pos < byte_pos
          tok = code.byteslice(prev_byte_pos...byte_pos)
          pos = [prev_line, prev_byte_pos - line_positions[prev_line - 1]]
          interpolated << Ripper::Lexer::Elem.new(pos, :on_ignored_by_ripper, tok, 0)
          prev_line += tok.count("\n")
        end
        interpolated << t
        prev_byte_pos = byte_pos + t.tok.bytesize
        prev_line += t.tok.count("\n")
      end
      if prev_byte_pos < code.bytesize
        tok = code.byteslice(prev_byte_pos..)
        pos = [prev_line, prev_byte_pos - line_positions[prev_line - 1]]
        interpolated << Ripper::Lexer::Elem.new(pos, :on_ignored_by_ripper, tok, 0)
      end
      interpolated
    end

    def self.ripper_lex_without_warning(code, local_variables: [])
      verbose, $VERBOSE = $VERBOSE, nil
      lvars_code = generate_local_variables_assign_code(local_variables)
      original_code = code
      if lvars_code
        code = "#{lvars_code}\n#{code}"
        line_no = 0
      else
        line_no = 1
      end

      compile_with_errors_suppressed(code, line_no: line_no) do |inner_code, line_no|
        lexer = Ripper::Lexer.new(inner_code, '-', line_no)
        tokens = []
        lexer.scan.each do |t|
          next if t.pos.first == 0
          prev_tk = tokens.last
          position_overlapped = prev_tk && t.pos[0] == prev_tk.pos[0] && t.pos[1] < prev_tk.pos[1] + prev_tk.tok.bytesize
          if position_overlapped
            tokens[-1] = t if ERROR_TOKENS.include?(prev_tk.event) && !ERROR_TOKENS.include?(t.event)
          else
            tokens << t
          end
        end
        interpolate_ripper_ignored_tokens(original_code, tokens)
      end
    ensure
      $VERBOSE = verbose
    end

    def check_code_state(code, local_variables:)
      tokens = self.class.ripper_lex_without_warning(code, local_variables: local_variables)
      opens = NestingParser.open_tokens(tokens)
      [tokens, opens, code_terminated?(code, tokens, opens, local_variables: local_variables)]
    end

    def code_terminated?(code, tokens, opens, local_variables:)
      case check_code_syntax(code, local_variables: local_variables)
      when :unrecoverable_error
        true
      when :recoverable_error
        false
      when :other_error
        opens.empty? && !should_continue?(tokens)
      when :valid
        !should_continue?(tokens)
      end
    end

    def assignment_expression?(code, local_variables:)
      # Try to parse the code and check if the last of possibly multiple
      # expressions is an assignment type.

      # If the expression is invalid, Ripper.sexp should return nil which will
      # result in false being returned. Any valid expression should return an
      # s-expression where the second element of the top level array is an
      # array of parsed expressions. The first element of each expression is the
      # expression's type.
      verbose, $VERBOSE = $VERBOSE, nil
      code = "#{RubyLex.generate_local_variables_assign_code(local_variables) || 'nil;'}\n#{code}"
      # Get the last node_type of the line. drop(1) is to ignore the local_variables_assign_code part.
      node_type = Ripper.sexp(code)&.dig(1)&.drop(1)&.dig(-1, 0)
      ASSIGNMENT_NODE_TYPES.include?(node_type)
    ensure
      $VERBOSE = verbose
    end

    def should_continue?(tokens)
      # Look at the last token and check if IRB need to continue reading next line.
      # Example code that should continue: `a\` `a +` `a.`
      # Trailing spaces, newline, comments are skipped
      return true if tokens.last&.event == :on_sp && tokens.last.tok == "\\\n"

      tokens.reverse_each do |token|
        case token.event
        when :on_sp, :on_nl, :on_ignored_nl, :on_comment, :on_embdoc_beg, :on_embdoc, :on_embdoc_end
          # Skip
        when :on_regexp_end, :on_heredoc_end, :on_semicolon
          # State is EXPR_BEG but should not continue
          return false
        else
          # Endless range should not continue
          return false if token.event == :on_op && token.tok.match?(/\A\.\.\.?\z/)

          # EXPR_DOT and most of the EXPR_BEG should continue
          return token.state.anybits?(Ripper::EXPR_BEG | Ripper::EXPR_DOT)
        end
      end
      false
    end

    def check_code_syntax(code, local_variables:)
      lvars_code = RubyLex.generate_local_variables_assign_code(local_variables)
      code = "#{lvars_code}\n#{code}"

      begin # check if parser error are available
        verbose, $VERBOSE = $VERBOSE, nil
        case RUBY_ENGINE
        when 'ruby'
          self.class.compile_with_errors_suppressed(code) do |inner_code, line_no|
            RubyVM::InstructionSequence.compile(inner_code, nil, nil, line_no)
          end
        when 'jruby'
          JRuby.compile_ir(code)
        else
          catch(:valid) do
            eval("BEGIN { throw :valid, true }\n#{code}")
            false
          end
        end
      rescue EncodingError
        # This is for a hash with invalid encoding symbol, {"\xAE": 1}
        :unrecoverable_error
      rescue SyntaxError => e
        case e.message
        when /unterminated (?:string|regexp) meets end of file/
          # "unterminated regexp meets end of file"
          #
          #   example:
          #     /
          #
          # "unterminated string meets end of file"
          #
          #   example:
          #     '
          return :recoverable_error
        when /syntax error, unexpected end-of-input/
          # "syntax error, unexpected end-of-input, expecting keyword_end"
          #
          #   example:
          #     if true
          #       hoge
          #       if false
          #         fuga
          #       end
          return :recoverable_error
        when /syntax error, unexpected keyword_end/
          # "syntax error, unexpected keyword_end"
          #
          #   example:
          #     if (
          #     end
          #
          #   example:
          #     end
          return :unrecoverable_error
        when /syntax error, unexpected '\.'/
          # "syntax error, unexpected '.'"
          #
          #   example:
          #     .
          return :unrecoverable_error
        when /unexpected tREGEXP_BEG/
          # "syntax error, unexpected tREGEXP_BEG, expecting keyword_do or '{' or '('"
          #
          #   example:
          #     method / f /
          return :unrecoverable_error
        else
          return :other_error
        end
      ensure
        $VERBOSE = verbose
      end
      :valid
    end

    def calc_indent_level(opens)
      indent_level = 0
      opens.each_with_index do |t, index|
        case t.event
        when :on_heredoc_beg
          if opens[index + 1]&.event != :on_heredoc_beg
            if t.tok.match?(/^<<[~-]/)
              indent_level += 1
            else
              indent_level = 0
            end
          end
        when :on_tstring_beg, :on_regexp_beg, :on_symbeg, :on_backtick
          # No indent: "", //, :"", ``
          # Indent: %(), %r(), %i(), %x()
          indent_level += 1 if t.tok.start_with? '%'
        when :on_embdoc_beg
          indent_level = 0
        else
          indent_level += 1 unless t.tok == 'alias' || t.tok == 'undef'
        end
      end
      indent_level
    end

    FREE_INDENT_TOKENS = %i[on_tstring_beg on_backtick on_regexp_beg on_symbeg]

    def free_indent_token?(token)
      FREE_INDENT_TOKENS.include?(token&.event)
    end

    # Calculates the difference of pasted code's indent and indent calculated from tokens
    def indent_difference(lines, line_results, line_index)
      loop do
        _tokens, prev_opens, _next_opens, min_depth = line_results[line_index]
        open_token = prev_opens.last
        if !open_token || (open_token.event != :on_heredoc_beg && !free_indent_token?(open_token))
          # If the leading whitespace is an indent, return the difference
          indent_level = calc_indent_level(prev_opens.take(min_depth))
          calculated_indent = 2 * indent_level
          actual_indent = lines[line_index][/^ */].size
          return actual_indent - calculated_indent
        elsif open_token.event == :on_heredoc_beg && open_token.tok.match?(/^<<[^-~]/)
          return 0
        end
        # If the leading whitespace is not an indent but part of a multiline token
        # Calculate base_indent of the multiline token's beginning line
        line_index = open_token.pos[0] - 1
      end
    end

    def process_indent_level(tokens, lines, line_index, is_newline)
      line_results = NestingParser.parse_by_line(tokens)
      result = line_results[line_index]
      if result
        _tokens, prev_opens, next_opens, min_depth = result
      else
        # When last line is empty
        prev_opens = next_opens = line_results.last[2]
        min_depth = next_opens.size
      end

      # To correctly indent line like `end.map do`, we use shortest open tokens on each line for indent calculation.
      # Shortest open tokens can be calculated by `opens.take(min_depth)`
      indent = 2 * calc_indent_level(prev_opens.take(min_depth))

      preserve_indent = lines[line_index - (is_newline ? 1 : 0)][/^ */].size

      prev_open_token = prev_opens.last
      next_open_token = next_opens.last

      # Calculates base indent for pasted code on the line where prev_open_token is located
      # irb(main):001:1*   if a # base_indent is 2, indent calculated from tokens is 0
      # irb(main):002:1*         if b # base_indent is 6, indent calculated from tokens is 2
      # irb(main):003:0>           c # base_indent is 6, indent calculated from tokens is 4
      if prev_open_token
        base_indent = [0, indent_difference(lines, line_results, prev_open_token.pos[0] - 1)].max
      else
        base_indent = 0
      end

      if free_indent_token?(prev_open_token)
        if is_newline && prev_open_token.pos[0] == line_index
          # First newline inside free-indent token
          base_indent + indent
        else
          # Accept any number of indent inside free-indent token
          preserve_indent
        end
      elsif prev_open_token&.event == :on_embdoc_beg || next_open_token&.event == :on_embdoc_beg
        if prev_open_token&.event == next_open_token&.event
          # Accept any number of indent inside embdoc content
          preserve_indent
        else
          # =begin or =end
          0
        end
      elsif prev_open_token&.event == :on_heredoc_beg
        tok = prev_open_token.tok
        if prev_opens.size <= next_opens.size
          if is_newline && lines[line_index].empty? && line_results[line_index - 1][1].last != next_open_token
            # First line in heredoc
            tok.match?(/^<<[-~]/) ? base_indent + indent : indent
          elsif tok.match?(/^<<~/)
            # Accept extra indent spaces inside `<<~` heredoc
            [base_indent + indent, preserve_indent].max
          else
            # Accept any number of indent inside other heredoc
            preserve_indent
          end
        else
          # Heredoc close
          prev_line_indent_level = calc_indent_level(prev_opens)
          tok.match?(/^<<[~-]/) ? base_indent + 2 * (prev_line_indent_level - 1) : 0
        end
      else
        base_indent + indent
      end
    end

    LTYPE_TOKENS = %i[
      on_heredoc_beg on_tstring_beg
      on_regexp_beg on_symbeg on_backtick
      on_symbols_beg on_qsymbols_beg
      on_words_beg on_qwords_beg
    ]

    def ltype_from_open_tokens(opens)
      start_token = opens.reverse_each.find do |tok|
        LTYPE_TOKENS.include?(tok.event)
      end
      return nil unless start_token

      case start_token&.event
      when :on_tstring_beg
        case start_token&.tok
        when ?"      then ?"
        when /^%.$/  then ?"
        when /^%Q.$/ then ?"
        when ?'      then ?'
        when /^%q.$/ then ?'
        end
      when :on_regexp_beg   then ?/
      when :on_symbeg       then ?:
      when :on_backtick     then ?`
      when :on_qwords_beg   then ?]
      when :on_words_beg    then ?]
      when :on_qsymbols_beg then ?]
      when :on_symbols_beg  then ?]
      when :on_heredoc_beg
        start_token&.tok =~ /<<[-~]?(['"`])\w+\1/
        $1 || ?"
      else
        nil
      end
    end

    def check_termination_in_prev_line(code, local_variables:)
      tokens = self.class.ripper_lex_without_warning(code, local_variables: local_variables)
      past_first_newline = false
      index = tokens.rindex do |t|
        # traverse first token before last line
        if past_first_newline
          if t.tok.include?("\n")
            true
          end
        elsif t.tok.include?("\n")
          past_first_newline = true
          false
        else
          false
        end
      end

      if index
        first_token = nil
        last_line_tokens = tokens[(index + 1)..(tokens.size - 1)]
        last_line_tokens.each do |t|
          unless [:on_sp, :on_ignored_sp, :on_comment].include?(t.event)
            first_token = t
            break
          end
        end

        if first_token && first_token.state != Ripper::EXPR_DOT
          tokens_without_last_line = tokens[0..index]
          code_without_last_line = tokens_without_last_line.map(&:tok).join
          opens_without_last_line = NestingParser.open_tokens(tokens_without_last_line)
          if code_terminated?(code_without_last_line, tokens_without_last_line, opens_without_last_line, local_variables: local_variables)
            return last_line_tokens.map(&:tok).join
          end
        end
      end
      false
    end
  end
  # :startdoc:
end

RubyLex = IRB::RubyLex
Object.deprecate_constant(:RubyLex)
