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

module Racc

  class LogFileGenerator

    def initialize(states, debug_flags = DebugFlags.new)
      @states = states
      @grammar = states.grammar
      @debug_flags = debug_flags
    end

    def output(out)
      output_conflict out; out.puts
      output_useless  out; out.puts
      output_rule     out; out.puts
      output_token    out; out.puts
      output_state    out
    end

    #
    # Warnings
    #

    def output_conflict(out)
      @states.each do |state|
        if state.srconf
          out.printf "state %d contains %d shift/reduce conflicts\n",
                     state.stateid, state.srconf.size
        end
        if state.rrconf
          out.printf "state %d contains %d reduce/reduce conflicts\n",
                     state.stateid, state.rrconf.size
        end
      end
    end

    def output_useless(out)
      @grammar.each do |rl|
        if rl.useless?
          out.printf "rule %d (%s) never reduced\n",
                     rl.ident, rl.target.to_s
        end
      end
      @grammar.each_nonterminal do |t|
        if t.useless?
          out.printf "useless nonterminal %s\n", t.to_s
        end
      end
    end

    #
    # States
    #

    def output_state(out)
      out << "--------- State ---------\n"

      showall = @debug_flags.la || @debug_flags.state
      @states.each do |state|
        out << "\nstate #{state.ident}\n\n"

        (showall ? state.closure : state.core).each do |ptr|
          pointer_out(out, ptr) if ptr.rule.ident != 0 or showall
        end
        out << "\n"

        action_out out, state
      end
    end

    def pointer_out(out, ptr)
      buf = sprintf("%4d) %s :", ptr.rule.ident, ptr.rule.target.to_s)
      ptr.rule.symbols.each_with_index do |tok, idx|
        buf << ' _' if idx == ptr.index
        buf << ' ' << tok.to_s
      end
      buf << ' _' if ptr.reduce?
      out.puts buf
    end

    def action_out(f, state)
      sr = state.srconf && state.srconf.dup
      rr = state.rrconf && state.rrconf.dup
      acts = state.action
      keys = acts.keys
      keys.sort! {|a,b| a.ident <=> b.ident }

      [ Shift, Reduce, Error, Accept ].each do |klass|
        keys.delete_if do |tok|
          act = acts[tok]
          if act.kind_of?(klass)
            outact f, tok, act
            if sr and c = sr.delete(tok)
              outsrconf f, c
            end
            if rr and c = rr.delete(tok)
              outrrconf f, c
            end

            true
          else
            false
          end
        end
      end
      sr.each {|tok, c| outsrconf f, c } if sr
      rr.each {|tok, c| outrrconf f, c } if rr

      act = state.defact
      if not act.kind_of?(Error) or @debug_flags.any?
        outact f, '$default', act
      end

      f.puts
      state.goto_table.each do |t, st|
        if t.nonterminal?
          f.printf "  %-12s  go to state %d\n", t.to_s, st.ident
        end
      end
    end

    def outact(f, t, act)
      case act
      when Shift
        f.printf "  %-12s  shift, and go to state %d\n",
                 t.to_s, act.goto_id
      when Reduce
        f.printf "  %-12s  reduce using rule %d (%s)\n",
                 t.to_s, act.ruleid, act.rule.target.to_s
      when Accept
        f.printf "  %-12s  accept\n", t.to_s
      when Error
        f.printf "  %-12s  error\n", t.to_s
      else
        raise "racc: fatal: wrong act for outact: act=#{act}(#{act.class})"
      end
    end

    def outsrconf(f, confs)
      confs.each do |c|
        r = c.reduce
        f.printf "  %-12s  [reduce using rule %d (%s)]\n",
                 c.shift.to_s, r.ident, r.target.to_s
      end
    end

    def outrrconf(f, confs)
      confs.each do |c|
        r = c.low_prec
        f.printf "  %-12s  [reduce using rule %d (%s)]\n",
                 c.token.to_s, r.ident, r.target.to_s
      end
    end

    #
    # Rules
    #

    def output_rule(out)
      out.print "-------- Grammar --------\n\n"
      @grammar.each do |rl|
        if @debug_flags.any? or rl.ident != 0
          out.printf "rule %d %s: %s\n",
                     rl.ident, rl.target.to_s, rl.symbols.join(' ')
        end
      end
    end

    #
    # Tokens
    #

    def output_token(out)
      out.print "------- Symbols -------\n\n"

      out.print "**Nonterminals, with rules where they appear\n\n"
      @grammar.each_nonterminal do |t|
        tmp = <<SRC
  %s (%d)
    on right: %s
    on left : %s
SRC
        out.printf tmp, t.to_s, t.ident,
                   symbol_locations(t.locate).join(' '),
                   symbol_locations(t.heads).join(' ')
      end

      out.print "\n**Terminals, with rules where they appear\n\n"
      @grammar.each_terminal do |t|
        out.printf "  %s (%d) %s\n",
                   t.to_s, t.ident, symbol_locations(t.locate).join(' ')
      end
    end

    def symbol_locations(locs)
      locs.map {|loc| loc.rule.ident }.reject {|n| n == 0 }.uniq
    end

  end

end   # module Racc
