# frozen_string_literal: false
#--
# Copyright (c) 1999-2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the same terms of ruby.
#
# As a special exception, when this code is copied by Racc
# into a Racc output file, you may use that output file
# without restriction.
#++

require 'racc/info'

unless defined?(NotImplementedError)
  NotImplementedError = NotImplementError # :nodoc:
end

module Racc
  class ParseError < StandardError; end
end
unless defined?(::ParseError)
  ParseError = Racc::ParseError
end

# Racc is a LALR(1) parser generator.
# It is written in Ruby itself, and generates Ruby programs.
#
# == Command-line Reference
#
#     racc [-o<var>filename</var>] [--output-file=<var>filename</var>]
#          [-e<var>rubypath</var>] [--executable=<var>rubypath</var>]
#          [-v] [--verbose]
#          [-O<var>filename</var>] [--log-file=<var>filename</var>]
#          [-g] [--debug]
#          [-E] [--embedded]
#          [-l] [--no-line-convert]
#          [-c] [--line-convert-all]
#          [-a] [--no-omit-actions]
#          [-C] [--check-only]
#          [-S] [--output-status]
#          [--version] [--copyright] [--help] <var>grammarfile</var>
#
# [+grammarfile+]
#   Racc grammar file. Any extension is permitted.
# [-o+outfile+, --output-file=+outfile+]
#   A filename for output. default is <+filename+>.tab.rb
# [-O+filename+, --log-file=+filename+]
#   Place logging output in file +filename+.
#   Default log file name is <+filename+>.output.
# [-e+rubypath+, --executable=+rubypath+]
#   output executable file(mode 755). where +path+ is the Ruby interpreter.
# [-v, --verbose]
#   verbose mode. create +filename+.output file, like yacc's y.output file.
# [-g, --debug]
#   add debug code to parser class. To display debuggin information,
#   use this '-g' option and set @yydebug true in parser class.
# [-E, --embedded]
#   Output parser which doesn't need runtime files (racc/parser.rb).
# [-C, --check-only]
#   Check syntax of racc grammar file and quit.
# [-S, --output-status]
#   Print messages time to time while compiling.
# [-l, --no-line-convert]
#   turns off line number converting.
# [-c, --line-convert-all]
#   Convert line number of actions, inner, header and footer.
# [-a, --no-omit-actions]
#   Call all actions, even if an action is empty.
# [--version]
#   print Racc version and quit.
# [--copyright]
#   Print copyright and quit.
# [--help]
#   Print usage and quit.
#
# == Generating Parser Using Racc
#
# To compile Racc grammar file, simply type:
#
#   $ racc parse.y
#
# This creates Ruby script file "parse.tab.y". The -o option can change the output filename.
#
# == Writing A Racc Grammar File
#
# If you want your own parser, you have to write a grammar file.
# A grammar file contains the name of your parser class, grammar for the parser,
# user code, and anything else.
# When writing a grammar file, yacc's knowledge is helpful.
# If you have not used yacc before, Racc is not too difficult.
#
# Here's an example Racc grammar file.
#
#   class Calcparser
#   rule
#     target: exp { print val[0] }
#
#     exp: exp '+' exp
#        | exp '*' exp
#        | '(' exp ')'
#        | NUMBER
#   end
#
# Racc grammar files resemble yacc files.
# But (of course), this is Ruby code.
# yacc's $$ is the 'result', $0, $1... is
# an array called 'val', and $-1, $-2... is an array called '_values'.
#
# See the {Grammar File Reference}[rdoc-ref:lib/racc/rdoc/grammar.en.rdoc] for
# more information on grammar files.
#
# == Parser
#
# Then you must prepare the parse entry method. There are two types of
# parse methods in Racc, Racc::Parser#do_parse and Racc::Parser#yyparse
#
# Racc::Parser#do_parse is simple.
#
# It's yyparse() of yacc, and Racc::Parser#next_token is yylex().
# This method must returns an array like [TOKENSYMBOL, ITS_VALUE].
# EOF is [false, false].
# (TOKENSYMBOL is a Ruby symbol (taken from String#intern) by default.
# If you want to change this, see the grammar reference.
#
# Racc::Parser#yyparse is little complicated, but useful.
# It does not use Racc::Parser#next_token, instead it gets tokens from any iterator.
#
# For example, <code>yyparse(obj, :scan)</code> causes
# calling +obj#scan+, and you can return tokens by yielding them from +obj#scan+.
#
# == Debugging
#
# When debugging, "-v" or/and the "-g" option is helpful.
#
# "-v" creates verbose log file (.output).
# "-g" creates a "Verbose Parser".
# Verbose Parser prints the internal status when parsing.
# But it's _not_ automatic.
# You must use -g option and set +@yydebug+ to +true+ in order to get output.
# -g option only creates the verbose parser.
#
# === Racc reported syntax error.
#
# Isn't there too many "end"?
# grammar of racc file is changed in v0.10.
#
# Racc does not use '%' mark, while yacc uses huge number of '%' marks..
#
# === Racc reported "XXXX conflicts".
#
# Try "racc -v xxxx.y".
# It causes producing racc's internal log file, xxxx.output.
#
# === Generated parsers does not work correctly
#
# Try "racc -g xxxx.y".
# This command let racc generate "debugging parser".
# Then set @yydebug=true in your parser.
# It produces a working log of your parser.
#
# == Re-distributing Racc runtime
#
# A parser, which is created by Racc, requires the Racc runtime module;
# racc/parser.rb.
#
# Ruby 1.8.x comes with Racc runtime module,
# you need NOT distribute Racc runtime files.
#
# If you want to include the Racc runtime module with your parser.
# This can be done by using '-E' option:
#
#   $ racc -E -omyparser.rb myparser.y
#
# This command creates myparser.rb which `includes' Racc runtime.
# Only you must do is to distribute your parser file (myparser.rb).
#
# Note: parser.rb is ruby license, but your parser is not.
# Your own parser is completely yours.
module Racc

  unless defined?(Racc_No_Extensions)
    Racc_No_Extensions = false # :nodoc:
  end

  class Parser

    Racc_Runtime_Version = ::Racc::VERSION
    Racc_Runtime_Core_Version_R = ::Racc::VERSION

    begin
      if Object.const_defined?(:RUBY_ENGINE) and RUBY_ENGINE == 'jruby'
        require 'jruby'
        require 'racc/cparse-jruby.jar'
        com.headius.racc.Cparse.new.load(JRuby.runtime, false)
      else
        require 'racc/cparse'
      end

      unless new.respond_to?(:_racc_do_parse_c, true)
        raise LoadError, 'old cparse.so'
      end
      if Racc_No_Extensions
        raise LoadError, 'selecting ruby version of racc runtime core'
      end

      Racc_Main_Parsing_Routine    = :_racc_do_parse_c # :nodoc:
      Racc_YY_Parse_Method         = :_racc_yyparse_c # :nodoc:
      Racc_Runtime_Core_Version    = Racc_Runtime_Core_Version_C # :nodoc:
      Racc_Runtime_Type            = 'c' # :nodoc:
    rescue LoadError
      Racc_Main_Parsing_Routine    = :_racc_do_parse_rb
      Racc_YY_Parse_Method         = :_racc_yyparse_rb
      Racc_Runtime_Core_Version    = Racc_Runtime_Core_Version_R
      Racc_Runtime_Type            = 'ruby'
    end

    def Parser.racc_runtime_type # :nodoc:
      Racc_Runtime_Type
    end

    def _racc_setup
      @yydebug = false unless self.class::Racc_debug_parser
      @yydebug = false unless defined?(@yydebug)
      if @yydebug
        @racc_debug_out = $stderr unless defined?(@racc_debug_out)
        @racc_debug_out ||= $stderr
      end
      arg = self.class::Racc_arg
      arg[13] = true if arg.size < 14
      arg
    end

    def _racc_init_sysvars
      @racc_state  = [0]
      @racc_tstack = []
      @racc_vstack = []

      @racc_t = nil
      @racc_val = nil

      @racc_read_next = true

      @racc_user_yyerror = false
      @racc_error_status = 0
    end

    # The entry point of the parser. This method is used with #next_token.
    # If Racc wants to get token (and its value), calls next_token.
    #
    # Example:
    #     def parse
    #       @q = [[1,1],
    #             [2,2],
    #             [3,3],
    #             [false, '$']]
    #       do_parse
    #     end
    #
    #     def next_token
    #       @q.shift
    #     end
    class_eval %{
    def do_parse
      #{Racc_Main_Parsing_Routine}(_racc_setup(), false)
    end
    }

    # The method to fetch next token.
    # If you use #do_parse method, you must implement #next_token.
    #
    # The format of return value is [TOKEN_SYMBOL, VALUE].
    # +token-symbol+ is represented by Ruby's symbol by default, e.g. :IDENT
    # for 'IDENT'.  ";" (String) for ';'.
    #
    # The final symbol (End of file) must be false.
    def next_token
      raise NotImplementedError, "#{self.class}\#next_token is not defined"
    end

    def _racc_do_parse_rb(arg, in_debug)
      action_table, action_check, action_default, action_pointer,
      _,            _,            _,              _,
      _,            _,            token_table,    * = arg

      _racc_init_sysvars
      tok = act = i = nil

      catch(:racc_end_parse) {
        while true
          if i = action_pointer[@racc_state[-1]]
            if @racc_read_next
              if @racc_t != 0   # not EOF
                tok, @racc_val = next_token()
                unless tok      # EOF
                  @racc_t = 0
                else
                  @racc_t = (token_table[tok] or 1)   # error token
                end
                racc_read_token(@racc_t, tok, @racc_val) if @yydebug
                @racc_read_next = false
              end
            end
            i += @racc_t
            unless i >= 0 and
                   act = action_table[i] and
                   action_check[i] == @racc_state[-1]
              act = action_default[@racc_state[-1]]
            end
          else
            act = action_default[@racc_state[-1]]
          end
          while act = _racc_evalact(act, arg)
            ;
          end
        end
      }
    end

    # Another entry point for the parser.
    # If you use this method, you must implement RECEIVER#METHOD_ID method.
    #
    # RECEIVER#METHOD_ID is a method to get next token.
    # It must 'yield' the token, which format is [TOKEN-SYMBOL, VALUE].
    class_eval %{
    def yyparse(recv, mid)
      #{Racc_YY_Parse_Method}(recv, mid, _racc_setup(), false)
    end
    }

    def _racc_yyparse_rb(recv, mid, arg, c_debug)
      action_table, action_check, action_default, action_pointer,
      _,            _,            _,              _,
      _,            _,            token_table,    * = arg

      _racc_init_sysvars

      catch(:racc_end_parse) {
        until i = action_pointer[@racc_state[-1]]
          while act = _racc_evalact(action_default[@racc_state[-1]], arg)
            ;
          end
        end
        recv.__send__(mid) do |tok, val|
          unless tok
            @racc_t = 0
          else
            @racc_t = (token_table[tok] or 1)   # error token
          end
          @racc_val = val
          @racc_read_next = false

          i += @racc_t
          unless i >= 0 and
                 act = action_table[i] and
                 action_check[i] == @racc_state[-1]
            act = action_default[@racc_state[-1]]
          end
          while act = _racc_evalact(act, arg)
            ;
          end

          while !(i = action_pointer[@racc_state[-1]]) ||
                ! @racc_read_next ||
                @racc_t == 0  # $
            unless i and i += @racc_t and
                   i >= 0 and
                   act = action_table[i] and
                   action_check[i] == @racc_state[-1]
              act = action_default[@racc_state[-1]]
            end
            while act = _racc_evalact(act, arg)
              ;
            end
          end
        end
      }
    end

    ###
    ### common
    ###

    def _racc_evalact(act, arg)
      action_table, action_check, _, action_pointer,
      _,            _,            _, _,
      _,            _,            _, shift_n,
      reduce_n,     * = arg
      nerr = 0   # tmp

      if act > 0 and act < shift_n
        #
        # shift
        #
        if @racc_error_status > 0
          @racc_error_status -= 1 unless @racc_t <= 1 # error token or EOF
        end
        @racc_vstack.push @racc_val
        @racc_state.push act
        @racc_read_next = true
        if @yydebug
          @racc_tstack.push @racc_t
          racc_shift @racc_t, @racc_tstack, @racc_vstack
        end

      elsif act < 0 and act > -reduce_n
        #
        # reduce
        #
        code = catch(:racc_jump) {
          @racc_state.push _racc_do_reduce(arg, act)
          false
        }
        if code
          case code
          when 1 # yyerror
            @racc_user_yyerror = true   # user_yyerror
            return -reduce_n
          when 2 # yyaccept
            return shift_n
          else
            raise '[Racc Bug] unknown jump code'
          end
        end

      elsif act == shift_n
        #
        # accept
        #
        racc_accept if @yydebug
        throw :racc_end_parse, @racc_vstack[0]

      elsif act == -reduce_n
        #
        # error
        #
        case @racc_error_status
        when 0
          unless arg[21]    # user_yyerror
            nerr += 1
            on_error @racc_t, @racc_val, @racc_vstack
          end
        when 3
          if @racc_t == 0   # is $
            # We're at EOF, and another error occurred immediately after
            # attempting auto-recovery
            throw :racc_end_parse, nil
          end
          @racc_read_next = true
        end
        @racc_user_yyerror = false
        @racc_error_status = 3
        while true
          if i = action_pointer[@racc_state[-1]]
            i += 1   # error token
            if  i >= 0 and
                (act = action_table[i]) and
                action_check[i] == @racc_state[-1]
              break
            end
          end
          throw :racc_end_parse, nil if @racc_state.size <= 1
          @racc_state.pop
          @racc_vstack.pop
          if @yydebug
            @racc_tstack.pop
            racc_e_pop @racc_state, @racc_tstack, @racc_vstack
          end
        end
        return act

      else
        raise "[Racc Bug] unknown action #{act.inspect}"
      end

      racc_next_state(@racc_state[-1], @racc_state) if @yydebug

      nil
    end

    def _racc_do_reduce(arg, act)
      _,          _,            _,            _,
      goto_table, goto_check,   goto_default, goto_pointer,
      nt_base,    reduce_table, _,            _,
      _,          use_result,   * = arg

      state = @racc_state
      vstack = @racc_vstack
      tstack = @racc_tstack

      i = act * -3
      len       = reduce_table[i]
      reduce_to = reduce_table[i+1]
      method_id = reduce_table[i+2]
      void_array = []

      tmp_t = tstack[-len, len] if @yydebug
      tmp_v = vstack[-len, len]
      tstack[-len, len] = void_array if @yydebug
      vstack[-len, len] = void_array
      state[-len, len]  = void_array

      # tstack must be updated AFTER method call
      if use_result
        vstack.push __send__(method_id, tmp_v, vstack, tmp_v[0])
      else
        vstack.push __send__(method_id, tmp_v, vstack)
      end
      tstack.push reduce_to

      racc_reduce(tmp_t, reduce_to, tstack, vstack) if @yydebug

      k1 = reduce_to - nt_base
      if i = goto_pointer[k1]
        i += state[-1]
        if i >= 0 and (curstate = goto_table[i]) and goto_check[i] == k1
          return curstate
        end
      end
      goto_default[k1]
    end

    # This method is called when a parse error is found.
    #
    # ERROR_TOKEN_ID is an internal ID of token which caused error.
    # You can get string representation of this ID by calling
    # #token_to_str.
    #
    # ERROR_VALUE is a value of error token.
    #
    # value_stack is a stack of symbol values.
    # DO NOT MODIFY this object.
    #
    # This method raises ParseError by default.
    #
    # If this method returns, parsers enter "error recovering mode".
    def on_error(t, val, vstack)
      raise ParseError, sprintf("\nparse error on value %s (%s)",
                                val.inspect, token_to_str(t) || '?')
    end

    # Enter error recovering mode.
    # This method does not call #on_error.
    def yyerror
      throw :racc_jump, 1
    end

    # Exit parser.
    # Return value is +Symbol_Value_Stack[0]+.
    def yyaccept
      throw :racc_jump, 2
    end

    # Leave error recovering mode.
    def yyerrok
      @racc_error_status = 0
    end

    # For debugging output
    def racc_read_token(t, tok, val)
      @racc_debug_out.print 'read    '
      @racc_debug_out.print tok.inspect, '(', racc_token2str(t), ') '
      @racc_debug_out.puts val.inspect
      @racc_debug_out.puts
    end

    def racc_shift(tok, tstack, vstack)
      @racc_debug_out.puts "shift   #{racc_token2str tok}"
      racc_print_stacks tstack, vstack
      @racc_debug_out.puts
    end

    def racc_reduce(toks, sim, tstack, vstack)
      out = @racc_debug_out
      out.print 'reduce '
      if toks.empty?
        out.print ' <none>'
      else
        toks.each {|t| out.print ' ', racc_token2str(t) }
      end
      out.puts " --> #{racc_token2str(sim)}"
      racc_print_stacks tstack, vstack
      @racc_debug_out.puts
    end

    def racc_accept
      @racc_debug_out.puts 'accept'
      @racc_debug_out.puts
    end

    def racc_e_pop(state, tstack, vstack)
      @racc_debug_out.puts 'error recovering mode: pop token'
      racc_print_states state
      racc_print_stacks tstack, vstack
      @racc_debug_out.puts
    end

    def racc_next_state(curstate, state)
      @racc_debug_out.puts  "goto    #{curstate}"
      racc_print_states state
      @racc_debug_out.puts
    end

    def racc_print_stacks(t, v)
      out = @racc_debug_out
      out.print '        ['
      t.each_index do |i|
        out.print ' (', racc_token2str(t[i]), ' ', v[i].inspect, ')'
      end
      out.puts ' ]'
    end

    def racc_print_states(s)
      out = @racc_debug_out
      out.print '        ['
      s.each {|st| out.print ' ', st }
      out.puts ' ]'
    end

    def racc_token2str(tok)
      self.class::Racc_token_to_s_table[tok] or
          raise "[Racc Bug] can't convert token #{tok} to string"
    end

    # Convert internal ID of token symbol to the string.
    def token_to_str(t)
      self.class::Racc_token_to_s_table[t]
    end

  end

end
