#--
#
#
#
# Copyright (c) 1999-2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the same terms of ruby.
# see the file "COPYING".
#
#++

require 'racc/parser'

module Racc

  StateTransitionTable = Struct.new(:action_table,
                                    :action_check,
                                    :action_default,
                                    :action_pointer,
                                    :goto_table,
                                    :goto_check,
                                    :goto_default,
                                    :goto_pointer,
                                    :token_table,
                                    :reduce_table,
                                    :reduce_n,
                                    :shift_n,
                                    :nt_base,
                                    :token_to_s_table,
                                    :use_result_var,
                                    :debug_parser)
  class StateTransitionTable   # reopen
    def StateTransitionTable.generate(states)
      StateTransitionTableGenerator.new(states).generate
    end

    def initialize(states)
      super()
      @states = states
      @grammar = states.grammar
      self.use_result_var = true
      self.debug_parser = true
    end

    attr_reader :states
    attr_reader :grammar

    def parser_class
      ParserClassGenerator.new(@states).generate
    end

    def token_value_table
      h = {}
      token_table().each do |sym, i|
        h[sym.value] = i
      end
      h
    end
  end


  class StateTransitionTableGenerator

    def initialize(states)
      @states = states
      @grammar = states.grammar
    end

    def generate
      t = StateTransitionTable.new(@states)
      gen_action_tables t, @states
      gen_goto_tables t, @grammar
      t.token_table = token_table(@grammar)
      t.reduce_table = reduce_table(@grammar)
      t.reduce_n = @states.reduce_n
      t.shift_n = @states.shift_n
      t.nt_base = @grammar.nonterminal_base
      t.token_to_s_table = @grammar.symbols.map {|sym| sym.to_s }
      t
    end

    def reduce_table(grammar)
      t = [0, 0, :racc_error]
      grammar.each_with_index do |rule, idx|
        next if idx == 0
        t.push rule.size
        t.push rule.target.ident
        t.push(if rule.action.empty?   # and @params.omit_action_call?
               then :_reduce_none
               else "_reduce_#{idx}".intern
               end)
      end
      t
    end

    def token_table(grammar)
      h = {}
      grammar.symboltable.terminals.each do |t|
        h[t] = t.ident
      end
      h
    end

    def gen_action_tables(t, states)
      t.action_table = yytable  = []
      t.action_check = yycheck  = []
      t.action_default = yydefact = []
      t.action_pointer = yypact   = []
      e1 = []
      e2 = []
      states.each do |state|
        yydefact.push act2actid(state.defact)
        if state.action.empty?
          yypact.push nil
          next
        end
        vector = []
        state.action.each do |tok, act|
          vector[tok.ident] = act2actid(act)
        end
        addent e1, vector, state.ident, yypact
      end
      set_table e1, e2, yytable, yycheck, yypact
    end

    def gen_goto_tables(t, grammar)
      t.goto_table   = yytable2  = []
      t.goto_check   = yycheck2  = []
      t.goto_pointer = yypgoto   = []
      t.goto_default = yydefgoto = []
      e1 = []
      e2 = []
      grammar.each_nonterminal do |tok|
        tmp = []

        # decide default
        freq = Array.new(@states.size, 0)
        @states.each do |state|
          st = state.goto_table[tok]
          if st
            st = st.ident
            freq[st] += 1
          end
          tmp[state.ident] = st
        end
        max = freq.max
        if max > 1
          default = freq.index(max)
          tmp.map! {|i| default == i ? nil : i }
        else
          default = nil
        end
        yydefgoto.push default

        # delete default value
        tmp.pop until tmp.last or tmp.empty?
        if tmp.compact.empty?
          # only default
          yypgoto.push nil
          next
        end

        addent e1, tmp, (tok.ident - grammar.nonterminal_base), yypgoto
      end
      set_table e1, e2, yytable2, yycheck2, yypgoto
    end

    def addent(all, arr, chkval, ptr)
      max = arr.size
      min = nil
      arr.each_with_index do |item, idx|
        if item
          min ||= idx
        end
      end
      ptr.push(-7777)    # mark
      arr = arr[min...max]
      all.push [arr, chkval, mkmapexp(arr), min, ptr.size - 1]
    end

    n = 2 ** 16
    begin
      Regexp.compile("a{#{n}}")
      RE_DUP_MAX = n
    rescue RegexpError
      n /= 2
      retry
    end

    def mkmapexp(arr)
      i = ii = 0
      as = arr.size
      map = String.new
      maxdup = RE_DUP_MAX
      curr = nil
      while i < as
        ii = i + 1
        if arr[i]
          ii += 1 while ii < as and arr[ii]
          curr = '-'
        else
          ii += 1 while ii < as and not arr[ii]
          curr = '.'
        end

        offset = ii - i
        if offset == 1
          map << curr
        else
          while offset > maxdup
            map << "#{curr}{#{maxdup}}"
            offset -= maxdup
          end
          map << "#{curr}{#{offset}}" if offset > 1
        end
        i = ii
      end
      Regexp.compile(map, 'n')
    end

    def set_table(entries, dummy, tbl, chk, ptr)
      upper = 0
      map = '-' * 10240

      # sort long to short
      entries.sort_by!.with_index {|a,i| [-a[0].size, i] }

      entries.each do |arr, chkval, expr, min, ptri|
        if upper + arr.size > map.size
          map << '-' * (arr.size + 1024)
        end
        idx = map.index(expr)
        ptr[ptri] = idx - min
        arr.each_with_index do |item, i|
          if item
            i += idx
            tbl[i] = item
            chk[i] = chkval
            map[i] = ?o
          end
        end
        upper = idx + arr.size
      end
    end

    def act2actid(act)
      case act
      when Shift  then act.goto_id
      when Reduce then -act.ruleid
      when Accept then @states.shift_n
      when Error  then @states.reduce_n * -1
      else
        raise "racc: fatal: wrong act type #{act.class} in action table"
      end
    end

  end


  class ParserClassGenerator

    def initialize(states)
      @states = states
      @grammar = states.grammar
    end

    def generate
      table = @states.state_transition_table
      c = Class.new(::Racc::Parser)
      c.const_set :Racc_arg, [table.action_table,
                              table.action_check,
                              table.action_default,
                              table.action_pointer,
                              table.goto_table,
                              table.goto_check,
                              table.goto_default,
                              table.goto_pointer,
                              table.nt_base,
                              table.reduce_table,
                              table.token_value_table,
                              table.shift_n,
                              table.reduce_n,
                              false]
      c.const_set :Racc_token_to_s_table, table.token_to_s_table
      c.const_set :Racc_debug_parser, true
      define_actions c
      c
    end

    private

    def define_actions(c)
      c.module_eval "def _reduce_none(vals, vstack) vals[0] end"
      @grammar.each do |rule|
        if rule.action.empty?
          c.alias_method("_reduce_#{rule.ident}", :_reduce_none)
        else
          c.define_method("_racc_action_#{rule.ident}", &rule.action.proc)
          c.module_eval(<<-End, __FILE__, __LINE__ + 1)
            def _reduce_#{rule.ident}(vals, vstack)
              _racc_action_#{rule.ident}(*vals)
            end
          End
        end
      end
    end

  end

end   # module Racc
