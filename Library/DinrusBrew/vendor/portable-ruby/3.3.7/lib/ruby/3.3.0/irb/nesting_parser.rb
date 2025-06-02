# frozen_string_literal: true
module IRB
  module NestingParser
    IGNORE_TOKENS = %i[on_sp on_ignored_nl on_comment on_embdoc_beg on_embdoc on_embdoc_end]

    # Scan each token and call the given block with array of token and other information for parsing
    def self.scan_opens(tokens)
      opens = []
      pending_heredocs = []
      first_token_on_line = true
      tokens.each do |t|
        skip = false
        last_tok, state, args = opens.last
        case state
        when :in_alias_undef
          skip = t.event == :on_kw
        when :in_unquoted_symbol
          unless IGNORE_TOKENS.include?(t.event)
            opens.pop
            skip = true
          end
        when :in_lambda_head
          opens.pop if t.event == :on_tlambeg || (t.event == :on_kw && t.tok == 'do')
        when :in_method_head
          unless IGNORE_TOKENS.include?(t.event)
            next_args = []
            body = nil
            if args.include?(:receiver)
              case t.event
              when :on_lparen, :on_ivar, :on_gvar, :on_cvar
                # def (receiver). | def @ivar. | def $gvar. | def @@cvar.
                next_args << :dot
              when :on_kw
                case t.tok
                when 'self', 'true', 'false', 'nil'
                  # def self(arg) | def self.
                  next_args.push(:arg, :dot)
                else
                  # def if(arg)
                  skip = true
                  next_args << :arg
                end
              when :on_op, :on_backtick
                # def +(arg)
                skip = true
                next_args << :arg
              when :on_ident, :on_const
                # def a(arg) | def a.
                next_args.push(:arg, :dot)
              end
            end
            if args.include?(:dot)
              # def receiver.name
              next_args << :name if t.event == :on_period || (t.event == :on_op && t.tok == '::')
            end
            if args.include?(:name)
              if %i[on_ident on_const on_op on_kw on_backtick].include?(t.event)
                # def name(arg) | def receiver.name(arg)
                next_args << :arg
                skip = true
              end
            end
            if args.include?(:arg)
              case t.event
              when :on_nl, :on_semicolon
                # def receiver.f;
                body = :normal
              when :on_lparen
                # def receiver.f()
                next_args << :eq
              else
                if t.event == :on_op && t.tok == '='
                  # def receiver.f =
                  body = :oneliner
                else
                  # def receiver.f arg
                  next_args << :arg_without_paren
                end
              end
            end
            if args.include?(:eq)
              if t.event == :on_op && t.tok == '='
                body = :oneliner
              else
                body = :normal
              end
            end
            if args.include?(:arg_without_paren)
              if %i[on_semicolon on_nl].include?(t.event)
                # def f a;
                body = :normal
              else
                # def f a, b
                next_args << :arg_without_paren
              end
            end
            if body == :oneliner
              opens.pop
            elsif body
              opens[-1] = [last_tok, nil]
            else
              opens[-1] = [last_tok, :in_method_head, next_args]
            end
          end
        when :in_for_while_until_condition
          if t.event == :on_semicolon || t.event == :on_nl || (t.event == :on_kw && t.tok == 'do')
            skip = true if t.event == :on_kw && t.tok == 'do'
            opens[-1] = [last_tok, nil]
          end
        end

        unless skip
          case t.event
          when :on_kw
            case t.tok
            when 'begin', 'class', 'module', 'do', 'case'
              opens << [t, nil]
            when 'end'
              opens.pop
            when 'def'
              opens << [t, :in_method_head, [:receiver, :name]]
            when 'if', 'unless'
              unless t.state.allbits?(Ripper::EXPR_LABEL)
                opens << [t, nil]
              end
            when 'while', 'until'
              unless t.state.allbits?(Ripper::EXPR_LABEL)
                opens << [t, :in_for_while_until_condition]
              end
            when 'ensure', 'rescue'
              unless t.state.allbits?(Ripper::EXPR_LABEL)
                opens.pop
                opens << [t, nil]
              end
            when 'alias'
              opens << [t, :in_alias_undef, 2]
            when 'undef'
              opens << [t, :in_alias_undef, 1]
            when 'elsif', 'else', 'when'
              opens.pop
              opens << [t, nil]
            when 'for'
              opens << [t, :in_for_while_until_condition]
            when 'in'
              if last_tok&.event == :on_kw && %w[case in].include?(last_tok.tok) && first_token_on_line
                opens.pop
                opens << [t, nil]
              end
            end
          when :on_tlambda
            opens << [t, :in_lambda_head]
          when :on_lparen, :on_lbracket, :on_lbrace, :on_tlambeg, :on_embexpr_beg, :on_embdoc_beg
            opens << [t, nil]
          when :on_rparen, :on_rbracket, :on_rbrace, :on_embexpr_end, :on_embdoc_end
            opens.pop
          when :on_heredoc_beg
            pending_heredocs << t
          when :on_heredoc_end
            opens.pop
          when :on_backtick
            opens << [t, nil] if t.state.allbits?(Ripper::EXPR_BEG)
          when :on_tstring_beg, :on_words_beg, :on_qwords_beg, :on_symbols_beg, :on_qsymbols_beg, :on_regexp_beg
            opens << [t, nil]
          when :on_tstring_end, :on_regexp_end, :on_label_end
            opens.pop
          when :on_symbeg
            if t.tok == ':'
              opens << [t, :in_unquoted_symbol]
            else
              opens << [t, nil]
            end
          end
        end
        if t.event == :on_nl || t.event == :on_semicolon
          first_token_on_line = true
        elsif t.event != :on_sp
          first_token_on_line = false
        end
        if pending_heredocs.any? && t.tok.include?("\n")
          pending_heredocs.reverse_each { |t| opens << [t, nil] }
          pending_heredocs = []
        end
        if opens.last && opens.last[1] == :in_alias_undef && !IGNORE_TOKENS.include?(t.event) && t.event != :on_heredoc_end
          tok, state, arg = opens.pop
          opens << [tok, state, arg - 1] if arg >= 1
        end
        yield t, opens if block_given?
      end
      opens.map(&:first) + pending_heredocs.reverse
    end

    def self.open_tokens(tokens)
      # scan_opens without block will return a list of open tokens at last token position
      scan_opens(tokens)
    end

    # Calculates token information [line_tokens, prev_opens, next_opens, min_depth] for each line.
    # Example code
    #   ["hello
    #   world"+(
    # First line
    #   line_tokens: [[lbracket, '['], [tstring_beg, '"'], [tstring_content("hello\nworld"), "hello\n"]]
    #   prev_opens:  []
    #   next_tokens: [lbracket, tstring_beg]
    #   min_depth:   0 (minimum at beginning of line)
    # Second line
    #   line_tokens: [[tstring_content("hello\nworld"), "world"], [tstring_end, '"'], [op, '+'], [lparen, '(']]
    #   prev_opens:  [lbracket, tstring_beg]
    #   next_tokens: [lbracket, lparen]
    #   min_depth:   1 (minimum just after tstring_end)
    def self.parse_by_line(tokens)
      line_tokens = []
      prev_opens = []
      min_depth = 0
      output = []
      last_opens = scan_opens(tokens) do |t, opens|
        depth = t == opens.last&.first ? opens.size - 1 : opens.size
        min_depth = depth if depth < min_depth
        if t.tok.include?("\n")
          t.tok.each_line do |line|
            line_tokens << [t, line]
            next if line[-1] != "\n"
            next_opens = opens.map(&:first)
            output << [line_tokens, prev_opens, next_opens, min_depth]
            prev_opens = next_opens
            min_depth = prev_opens.size
            line_tokens = []
          end
        else
          line_tokens << [t, t.tok]
        end
      end
      output << [line_tokens, prev_opens, last_opens, min_depth] if line_tokens.any?
      output
    end
  end
end
