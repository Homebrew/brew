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

require 'racc/compat'
require 'racc/iset'
require 'racc/sourcetext'
require 'racc/logfilegenerator'
require 'racc/exception'
require 'forwardable'

module Racc

  class Grammar

    def initialize(debug_flags = DebugFlags.new)
      @symboltable = SymbolTable.new
      @debug_symbol = debug_flags.token
      @rules   = []  # :: [Rule]
      @start   = nil
      @n_expected_srconflicts = nil
      @prec_table = []
      @prec_table_closed = false
      @closed = false
      @states = nil
    end

    attr_reader :start
    attr_reader :symboltable
    attr_accessor :n_expected_srconflicts

    def [](x)
      @rules[x]
    end

    def each_rule(&block)
      @rules.each(&block)
    end

    alias each each_rule

    def each_index(&block)
      @rules.each_index(&block)
    end

    def each_with_index(&block)
      @rules.each_with_index(&block)
    end

    def size
      @rules.size
    end

    def to_s
      "<Racc::Grammar>"
    end

    extend Forwardable

    def_delegator "@symboltable", :each, :each_symbol
    def_delegator "@symboltable", :each_terminal
    def_delegator "@symboltable", :each_nonterminal

    def intern(value, dummy = false)
      @symboltable.intern(value, dummy)
    end

    def symbols
      @symboltable.symbols
    end

    def nonterminal_base
      @symboltable.nt_base
    end

    def useless_nonterminal_exist?
      n_useless_nonterminals() != 0
    end

    def n_useless_nonterminals
      @n_useless_nonterminals ||= each_useless_nonterminal.count
    end

    def each_useless_nonterminal
      return to_enum __method__ unless block_given?

      @symboltable.each_nonterminal do |sym|
        yield sym if sym.useless?
      end
    end

    def useless_rule_exist?
      n_useless_rules() != 0
    end

    def n_useless_rules
      @n_useless_rules ||= each_useless_rule.count
    end

    def each_useless_rule
      return to_enum __method__ unless block_given?

      each do |r|
        yield r if r.useless?
      end
    end

    def nfa
      (@states ||= States.new(self)).nfa
    end

    def dfa
      (@states ||= States.new(self)).dfa
    end

    alias states dfa

    def state_transition_table
      states().state_transition_table
    end

    def parser_class
      states = states()   # cache
      if $DEBUG
        srcfilename = caller(1).first.slice(/\A(.*?):/, 1)
        begin
          write_log srcfilename + ".output"
        rescue SystemCallError
        end
        report = lambda {|s| $stderr.puts "racc: #{srcfilename}: #{s}" }
        if states.should_report_srconflict?
          report["#{states.n_srconflicts} shift/reduce conflicts"]
        end
        if states.rrconflict_exist?
          report["#{states.n_rrconflicts} reduce/reduce conflicts"]
        end
        g = states.grammar
        if g.useless_nonterminal_exist?
          report["#{g.n_useless_nonterminals} useless nonterminals"]
        end
        if g.useless_rule_exist?
          report["#{g.n_useless_rules} useless rules"]
        end
      end
      states.state_transition_table.parser_class
    end

    def write_log(path)
      File.open(path, 'w') {|f|
        LogFileGenerator.new(states()).output f
      }
    end

    #
    # Grammar Definition Interface
    #

    def add(rule)
      raise ArgumentError, "rule added after the Grammar closed" if @closed
      @rules.push rule
    end

    def added?(sym)
      @rules.detect {|r| r.target == sym }
    end

    def start_symbol=(s)
      raise CompileError, "start symbol set twice'" if @start
      @start = s
    end

    def declare_precedence(assoc, syms)
      raise CompileError, "precedence table defined twice" if @prec_table_closed
      @prec_table.push [assoc, syms]
    end

    def end_precedence_declaration(reverse)
      @prec_table_closed = true
      return if @prec_table.empty?
      table = reverse ? @prec_table.reverse : @prec_table
      table.each_with_index do |(assoc, syms), idx|
        syms.each do |sym|
          sym.assoc = assoc
          sym.precedence = idx
        end
      end
    end

    #
    # Dynamic Generation Interface
    #

    def Grammar.define(&block)
      env = DefinitionEnv.new
      env.instance_eval(&block)
      env.grammar
    end

    class DefinitionEnv
      def initialize
        @grammar = Grammar.new
        @seqs = Hash.new(0)
        @delayed = []
      end

      def grammar
        flush_delayed
        @grammar.each do |rule|
          if rule.specified_prec
            rule.specified_prec = @grammar.intern(rule.specified_prec)
          end
        end
        @grammar.init
        @grammar
      end

      def precedence_table(&block)
        env = PrecedenceDefinitionEnv.new(@grammar)
        env.instance_eval(&block)
        @grammar.end_precedence_declaration env.reverse
      end

      def method_missing(mid, *args, &block)
        unless mid.to_s[-1,1] == '='
          super   # raises NoMethodError
        end
        target = @grammar.intern(mid.to_s.chop.intern)
        unless args.size == 1
          raise ArgumentError, "too many arguments for #{mid} (#{args.size} for 1)"
        end
        _add target, args.first
      end

      def _add(target, x)
        case x
        when Sym
          @delayed.each do |rule|
            rule.replace x, target if rule.target == x
          end
          @grammar.symboltable.delete x
        else
          x.each_rule do |r|
            r.target = target
            @grammar.add r
          end
        end
        flush_delayed
      end

      def _delayed_add(rule)
        @delayed.push rule
      end

      def _added?(sym)
        @grammar.added?(sym) or @delayed.detect {|r| r.target == sym }
      end

      def flush_delayed
        return if @delayed.empty?
        @delayed.each do |rule|
          @grammar.add rule
        end
        @delayed.clear
      end

      def seq(*list, &block)
        Rule.new(nil, list.map {|x| _intern(x) }, UserAction.proc(block))
      end

      def null(&block)
        seq(&block)
      end

      def action(&block)
        id = "@#{@seqs["action"] += 1}".intern
        _delayed_add Rule.new(@grammar.intern(id), [], UserAction.proc(block))
        id
      end

      alias _ action

      def option(sym, default = nil, &block)
        _defmetasyntax("option", _intern(sym), block) {|target|
          seq() { default } | seq(sym)
        }
      end

      def many(sym, &block)
        _defmetasyntax("many", _intern(sym), block) {|target|
            seq() { [] }\
          | seq(target, sym) {|list, x| list.push x; list }
        }
      end

      def many1(sym, &block)
        _defmetasyntax("many1", _intern(sym), block) {|target|
            seq(sym) {|x| [x] }\
          | seq(target, sym) {|list, x| list.push x; list }
        }
      end

      def separated_by(sep, sym, &block)
        option(separated_by1(sep, sym), [], &block)
      end

      def separated_by1(sep, sym, &block)
        _defmetasyntax("separated_by1", _intern(sym), block) {|target|
            seq(sym) {|x| [x] }\
          | seq(target, sep, sym) {|list, _, x| list.push x; list }
        }
      end

      def _intern(x)
        case x
        when Symbol, String
          @grammar.intern(x)
        when Racc::Sym
          x
        else
          raise TypeError, "wrong type #{x.class} (expected Symbol/String/Racc::Sym)"
        end
      end

      private

      def _defmetasyntax(type, id, action, &block)
        if action
          idbase = "#{type}@#{id}-#{@seqs[type] += 1}"
          target = _wrap(idbase, "#{idbase}-core", action)
          _register("#{idbase}-core", &block)
        else
          target = _register("#{type}@#{id}", &block)
        end
        @grammar.intern(target)
      end

      def _register(target_name)
        target = target_name.intern
        unless _added?(@grammar.intern(target))
          yield(target).each_rule do |rule|
            rule.target = @grammar.intern(target)
            _delayed_add rule
          end
        end
        target
      end

      def _wrap(target_name, sym, block)
        target = target_name.intern
        _delayed_add Rule.new(@grammar.intern(target),
                              [@grammar.intern(sym.intern)],
                              UserAction.proc(block))
        target
      end
    end

    class PrecedenceDefinitionEnv
      def initialize(g)
        @grammar = g
        @prechigh_seen = false
        @preclow_seen = false
        @reverse = false
      end

      attr_reader :reverse

      def higher
        if @prechigh_seen
          raise CompileError, "prechigh used twice"
        end
        @prechigh_seen = true
      end

      def lower
        if @preclow_seen
          raise CompileError, "preclow used twice"
        end
        if @prechigh_seen
          @reverse = true
        end
        @preclow_seen = true
      end

      def left(*syms)
        @grammar.declare_precedence :Left, syms.map {|s| @grammar.intern(s) }
      end

      def right(*syms)
        @grammar.declare_precedence :Right, syms.map {|s| @grammar.intern(s) }
      end

      def nonassoc(*syms)
        @grammar.declare_precedence :Nonassoc, syms.map {|s| @grammar.intern(s)}
      end
    end

    #
    # Computation
    #

    def init
      return if @closed
      @closed = true
      @start ||= @rules.map {|r| r.target }.detect {|sym| not sym.dummy? }
      raise CompileError, 'no rule in input' if @rules.empty?
      add_start_rule
      @rules.freeze
      fix_ident
      compute_hash
      compute_heads
      determine_terminals
      compute_nullable_0
      @symboltable.fix
      compute_locate
      @symboltable.each_nonterminal {|t| compute_expand t }
      compute_nullable
      compute_useless
    end

    private

    def add_start_rule
      r = Rule.new(@symboltable.dummy,
                   [@start, @symboltable.anchor, @symboltable.anchor],
                   UserAction.empty)
      r.ident = 0
      r.hash = 0
      r.precedence = nil
      @rules.unshift r
    end

    # Rule#ident
    # LocationPointer#ident
    def fix_ident
      @rules.each_with_index do |rule, idx|
        rule.ident = idx
      end
    end

    # Rule#hash
    def compute_hash
      hash = 4   # size of dummy rule
      @rules.each do |rule|
        rule.hash = hash
        hash += (rule.size + 1)
      end
    end

    # Sym#heads
    def compute_heads
      @rules.each do |rule|
        rule.target.heads.push rule.ptrs[0]
      end
    end

    # Sym#terminal?
    def determine_terminals
      @symboltable.each do |s|
        s.term = s.heads.empty?
      end
    end

    # Sym#self_null?
    def compute_nullable_0
      @symboltable.each do |s|
        if s.terminal?
          s.snull = false
        else
          s.snull = s.heads.any? {|loc| loc.reduce? }
        end
      end
    end

    # Sym#locate
    def compute_locate
      @rules.each do |rule|
        t = nil
        rule.ptrs.each do |ptr|
          unless ptr.reduce?
            tok = ptr.dereference
            tok.locate.push ptr
            t = tok if tok.terminal?
          end
        end
        rule.precedence = t
      end
    end

    # Sym#expand
    def compute_expand(t)
      puts "expand> #{t.to_s}" if @debug_symbol
      t.expand = _compute_expand(t, ISet.new, [])
      puts "expand< #{t.to_s}: #{t.expand.to_s}" if @debug_symbol
    end

    def _compute_expand(t, set, lock)
      if tmp = t.expand
        set.update tmp
        return set
      end
      tok = nil
      set.update_a t.heads
      t.heads.each do |ptr|
        tok = ptr.dereference
        if tok and tok.nonterminal?
          unless lock[tok.ident]
            lock[tok.ident] = true
            _compute_expand tok, set, lock
          end
        end
      end
      set
    end

    # Sym#nullable?, Rule#nullable?
    def compute_nullable
      @rules.each       {|r| r.null = false }
      @symboltable.each {|t| t.null = false }
      r = @rules.dup
      s = @symboltable.nonterminals
      begin
        rs = r.size
        ss = s.size
        check_rules_nullable r
        check_symbols_nullable s
      end until rs == r.size and ss == s.size
    end

    def check_rules_nullable(rules)
      rules.delete_if do |rule|
        rule.null = true
        rule.symbols.each do |t|
          unless t.nullable?
            rule.null = false
            break
          end
        end
        rule.nullable?
      end
    end

    def check_symbols_nullable(symbols)
      symbols.delete_if do |sym|
        sym.heads.each do |ptr|
          if ptr.rule.nullable?
            sym.null = true
            break
          end
        end
        sym.nullable?
      end
    end

    # Sym#useless?, Rule#useless?
    # FIXME: what means "useless"?
    def compute_useless
      @symboltable.each_terminal {|sym| sym.useless = false }
      @symboltable.each_nonterminal {|sym| sym.useless = true }
      @rules.each {|rule| rule.useless = true }
      r = @rules.dup
      s = @symboltable.nonterminals
      begin
        rs = r.size
        ss = s.size
        check_rules_useless r
        check_symbols_useless s
      end until r.size == rs and s.size == ss
    end

    def check_rules_useless(rules)
      rules.delete_if do |rule|
        rule.useless = false
        rule.symbols.each do |sym|
          if sym.useless?
            rule.useless = true
            break
          end
        end
        not rule.useless?
      end
    end

    def check_symbols_useless(s)
      s.delete_if do |t|
        t.heads.each do |ptr|
          unless ptr.rule.useless?
            t.useless = false
            break
          end
        end
        not t.useless?
      end
    end

  end   # class Grammar


  class Rule

    def initialize(target, syms, act)
      @target = target
      @symbols = syms
      @action = act
      @alternatives = []

      @ident = nil
      @hash = nil
      @ptrs = nil
      @precedence = nil
      @specified_prec = nil
      @null = nil
      @useless = nil
    end

    attr_accessor :target
    attr_reader :symbols
    attr_reader :action

    def |(x)
      @alternatives.push x.rule
      self
    end

    def rule
      self
    end

    def each_rule(&block)
      yield self
      @alternatives.each(&block)
    end

    attr_accessor :ident

    attr_reader :hash
    attr_reader :ptrs

    def hash=(n)
      @hash = n
      ptrs = []
      @symbols.each_with_index do |sym, idx|
        ptrs.push LocationPointer.new(self, idx, sym)
      end
      ptrs.push LocationPointer.new(self, @symbols.size, nil)
      @ptrs = ptrs
    end

    def precedence
      @specified_prec || @precedence
    end

    def precedence=(sym)
      @precedence ||= sym
    end

    def prec(sym, &block)
      @specified_prec = sym
      if block
        unless @action.empty?
          raise CompileError, 'both of rule action block and prec block given'
        end
        @action = UserAction.proc(block)
      end
      self
    end

    attr_accessor :specified_prec

    def nullable?() @null end
    def null=(n)    @null = n end

    def useless?()  @useless end
    def useless=(u) @useless = u end

    def inspect
      "#<Racc::Rule id=#{@ident} (#{@target})>"
    end

    def ==(other)
      other.kind_of?(Rule) and @ident == other.ident
    end

    def [](idx)
      @symbols[idx]
    end

    def size
      @symbols.size
    end

    def empty?
      @symbols.empty?
    end

    def to_s
      "#<rule#{@ident}>"
    end

    def accept?
      if tok = @symbols[-1]
        tok.anchor?
      else
        false
      end
    end

    def each(&block)
      @symbols.each(&block)
    end

    def replace(src, dest)
      @target = dest
      @symbols = @symbols.map {|s| s == src ? dest : s }
    end

  end   # class Rule


  class UserAction

    def UserAction.source_text(src)
      new(src, nil)
    end

    def UserAction.proc(pr = nil, &block)
      if pr and block
        raise ArgumentError, "both of argument and block given"
      end
      new(nil, pr || block)
    end

    def UserAction.empty
      new(nil, nil)
    end

    private_class_method :new

    def initialize(src, proc)
      @source = src
      @proc = proc
    end

    attr_reader :source
    attr_reader :proc

    def source?
      not @proc
    end

    def proc?
      not @source
    end

    def empty?
      not @proc and not @source
    end

    def name
      "{action type=#{@source || @proc || 'nil'}}"
    end

    alias inspect name

  end


  class OrMark
    def initialize(lineno)
      @lineno = lineno
    end

    def name
      '|'
    end

    alias inspect name

    attr_reader :lineno
  end


  class Prec
    def initialize(symbol, lineno)
      @symbol = symbol
      @lineno = lineno
    end

    def name
      "=#{@symbol}"
    end

    alias inspect name

    attr_reader :symbol
    attr_reader :lineno
  end


  #
  # A set of rule and position in it's RHS.
  # Note that the number of pointers is more than rule's RHS array,
  # because pointer points right edge of the final symbol when reducing.
  #
  class LocationPointer

    def initialize(rule, i, sym)
      @rule   = rule
      @index  = i
      @symbol = sym
      @ident  = @rule.hash + i
      @reduce = sym.nil?
    end

    attr_reader :rule
    attr_reader :index
    attr_reader :symbol

    alias dereference symbol

    attr_reader :ident
    alias hash ident
    attr_reader :reduce
    alias reduce? reduce

    def to_s
      sprintf('(%d,%d %s)',
              @rule.ident, @index, (reduce?() ? '#' : @symbol.to_s))
    end

    alias inspect to_s

    def eql?(ot)
      @hash == ot.hash
    end

    alias == eql?

    def head?
      @index == 0
    end

    def next
      @rule.ptrs[@index + 1] or ptr_bug!
    end

    alias increment next

    def before(len)
      @rule.ptrs[@index - len] or ptr_bug!
    end

    private

    def ptr_bug!
      raise "racc: fatal: pointer not exist: self: #{to_s}"
    end

  end   # class LocationPointer


  class SymbolTable

    include Enumerable

    def initialize
      @symbols = []   # :: [Racc::Sym]
      @cache   = {}   # :: {(String|Symbol) => Racc::Sym}
      @dummy  = intern(:$start, true)
      @anchor = intern(false, true)     # Symbol ID = 0
      @error  = intern(:error, false)   # Symbol ID = 1
    end

    attr_reader :dummy
    attr_reader :anchor
    attr_reader :error

    def [](id)
      @symbols[id]
    end

    def intern(val, dummy = false)
      @cache[val] ||=
          begin
            sym = Sym.new(val, dummy)
            @symbols.push sym
            sym
          end
    end

    attr_reader :symbols
    alias to_a symbols

    def delete(sym)
      @symbols.delete sym
      @cache.delete sym.value
    end

    attr_reader :nt_base

    def nt_max
      @symbols.size
    end

    def each(&block)
      @symbols.each(&block)
    end

    def terminals(&block)
      @symbols[0, @nt_base]
    end

    def each_terminal(&block)
      @terms.each(&block)
    end

    def nonterminals
      @symbols[@nt_base, @symbols.size - @nt_base]
    end

    def each_nonterminal(&block)
      @nterms.each(&block)
    end

    def fix
      terms, nterms = @symbols.partition {|s| s.terminal? }
      @symbols = terms + nterms
      @terms = terms
      @nterms = nterms
      @nt_base = terms.size
      fix_ident
      check_terminals
    end

    private

    def fix_ident
      @symbols.each_with_index do |t, i|
        t.ident = i
      end
    end

    def check_terminals
      return unless @symbols.any? {|s| s.should_terminal? }
      @anchor.should_terminal
      @error.should_terminal
      each_terminal do |t|
        t.should_terminal if t.string_symbol?
      end
      each do |s|
        s.should_terminal if s.assoc
      end
      terminals().reject {|t| t.should_terminal? }.each do |t|
        raise CompileError, "terminal #{t} not declared as terminal"
      end
      nonterminals().select {|n| n.should_terminal? }.each do |n|
        raise CompileError, "symbol #{n} declared as terminal but is not terminal"
      end
    end

  end   # class SymbolTable


  # Stands terminal and nonterminal symbols.
  class Sym

    def initialize(value, dummyp)
      @ident = nil
      @value = value
      @dummyp = dummyp

      @term  = nil
      @nterm = nil
      @should_terminal = false
      @precedence = nil
      case value
      when Symbol
        @to_s = value.to_s
        @serialized = value.inspect
        @string = false
      when String
        @to_s = value.inspect
        @serialized = value.dump
        @string = true
      when false
        @to_s = '$end'
        @serialized = 'false'
        @string = false
      when ErrorSymbolValue
        @to_s = 'error'
        @serialized = 'Object.new'
        @string = false
      else
        raise ArgumentError, "unknown symbol value: #{value.class}"
      end

      @heads    = []
      @locate   = []
      @snull    = nil
      @null     = nil
      @expand   = nil
      @useless  = nil
    end

    class << self
      def once_writer(nm)
        nm = nm.id2name
        module_eval(<<-EOS)
          def #{nm}=(v)
            raise 'racc: fatal: @#{nm} != nil' unless @#{nm}.nil?
            @#{nm} = v
          end
        EOS
      end
    end

    once_writer :ident
    attr_reader :ident

    alias hash ident

    attr_reader :value

    def dummy?
      @dummyp
    end

    def terminal?
      @term
    end

    def nonterminal?
      @nterm
    end

    def term=(t)
      raise 'racc: fatal: term= called twice' unless @term.nil?
      @term = t
      @nterm = !t
    end

    def should_terminal
      @should_terminal = true
    end

    def should_terminal?
      @should_terminal
    end

    def string_symbol?
      @string
    end

    def serialize
      @serialized
    end

    attr_writer :serialized

    attr_accessor :precedence
    attr_accessor :assoc

    def to_s
      @to_s.dup
    end

    alias inspect to_s

    def |(x)
      rule() | x.rule
    end

    def rule
      Rule.new(nil, [self], UserAction.empty)
    end

    #
    # cache
    #

    attr_reader :heads
    attr_reader :locate

    def self_null?
      @snull
    end

    once_writer :snull

    def nullable?
      @null
    end

    def null=(n)
      @null = n
    end

    attr_reader :expand
    once_writer :expand

    def useless?
      @useless
    end

    def useless=(f)
      @useless = f
    end

  end   # class Sym

end   # module Racc
