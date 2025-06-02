require 'ripper'

module PowerAssert
  class Parser
    Ident = Struct.new(:type, :name, :column)

    attr_reader :line, :path, :lineno, :binding

    def initialize(line, path, lineno, binding, assertion_method_name = nil, assertion_proc = nil)
      @line = line
      @line_for_parsing = (valid_syntax?(line) ? line : slice_expression(line)).b
      @path = path
      @lineno = lineno
      @binding = binding
      @proc_local_variables = binding.eval('local_variables').map(&:to_s)
      @assertion_method_name = assertion_method_name
      @assertion_proc = assertion_proc
    end

    def idents
      @idents ||= extract_idents(Ripper.sexp(@line_for_parsing))
    end

    def call_paths
      collect_paths(idents).uniq
    end

    def method_id_set
      methods = idents.flatten.find_all {|i| i.type == :method }
      @method_id_set ||= methods.map(&:name).map(&:to_sym).each_with_object({}) {|i, h| h[i] = true }
    end

    private

    def valid_syntax?(str)
      return true unless defined?(RubyVM)
      begin
        verbose, $VERBOSE = $VERBOSE, nil
        RubyVM::InstructionSequence.compile(str)
        true
      rescue SyntaxError
        false
      ensure
        $VERBOSE = verbose
      end
    end

    def slice_expression(str)
      str = str.chomp
      str.sub!(/\A\s*(?:if|unless|elsif|case|while|until) /) {|i| ' ' * i.length }
      str.sub!(/\A\s*(?:\}|\]|end)?\./) {|i| ' ' * i.length }
      str.sub!(/[\{\.\\]\z/, '')
      str.sub!(/(?:&&|\|\|)\z/, '')
      str.sub!(/ (?:do|and|or)\z/, '')
      str
    end

    class Branch < Array
    end

    AND_OR_OPS = %i(and or && ||)

    #
    # Returns idents as graph structure.
    #
    #                                                  +--c--b--+
    #  extract_idents(Ripper.sexp('a&.b(c).d')) #=> a--+        +--d
    #                                                  +--------+
    #
    def extract_idents(sexp)
      tag, * = sexp
      case tag
      when :arg_paren, :assoc_splat, :fcall, :hash, :method_add_block, :string_literal, :return
        extract_idents(sexp[1])
      when :assign, :massign
        extract_idents(sexp[2])
      when :opassign
        _, _, (_, op_name, (_, op_column)), s0 = sexp
        extract_idents(s0) + [Ident[:method, op_name.sub(/=\z/, ''), op_column]]
      when :dyna_symbol
        if sexp[1][0].kind_of?(Symbol)
          # sexp[1] can be [:string_content, [..]] while parsing { "a": 1 }
          extract_idents(sexp[1])
        else
          sexp[1].flat_map {|s| extract_idents(s) }
        end
      when :assoclist_from_args, :bare_assoc_hash, :paren, :string_embexpr,
        :regexp_literal, :xstring_literal
        sexp[1].flat_map {|s| extract_idents(s) }
      when :command
        [sexp[2], sexp[1]].flat_map {|s| extract_idents(s) }
      when :assoc_new, :dot2, :dot3, :string_content
        sexp[1..-1].flat_map {|s| extract_idents(s) }
      when :unary
        handle_columnless_ident([], sexp[1], extract_idents(sexp[2]))
      when :binary
        op = sexp[2]
        if AND_OR_OPS.include?(op)
          extract_idents(sexp[1]) + [Branch[extract_idents(sexp[3]), []]]
        else
          handle_columnless_ident(extract_idents(sexp[1]), op, extract_idents(sexp[3]))
        end
      when :call
        _, recv, (op_sym, op_name, _), method = sexp
        with_safe_op = ((op_sym == :@op and op_name == '&.') or op_sym == :"&.")
        if method == :call
          handle_columnless_ident(extract_idents(recv), :call, [], with_safe_op)
        else
          extract_idents(recv) + (with_safe_op ? [Branch[extract_idents(method), []]] : extract_idents(method))
        end
      when :array
        sexp[1] ? sexp[1].flat_map {|s| extract_idents(s) } : []
      when :command_call
        [sexp[1], sexp[4], sexp[3]].flat_map {|s| extract_idents(s) }
      when :aref
        handle_columnless_ident(extract_idents(sexp[1]), :[], extract_idents(sexp[2]))
      when :method_add_arg
        idents = extract_idents(sexp[1])
        if idents.empty?
          # idents may be empty(e.g. ->{}.())
          extract_idents(sexp[2])
        else
          if idents[-1].kind_of?(Branch) and idents[-1][1].empty?
            # Safe navigation operator is used. See :call clause also.
            idents[0..-2] + [Branch[extract_idents(sexp[2]) + idents[-1][0], []]]
          else
            idents[0..-2] + extract_idents(sexp[2]) + [idents[-1]]
          end
        end
      when :args_add_block
        _, (tag, ss0, *ss1), _ = sexp
        if tag == :args_add_star
          (ss0 + ss1).flat_map {|s| extract_idents(s) }
        else
          sexp[1].flat_map {|s| extract_idents(s) }
        end
      when :vcall
        _, (tag, name, (_, column)) = sexp
        if tag == :@ident
          [Ident[@proc_local_variables.include?(name) ? :ref : :method, name, column]]
        else
          []
        end
      when :program
        _, ((tag0, (tag1, (tag2, (tag3, mname, _)), _), (tag4, _, ss))) = sexp
        if tag0 == :method_add_block and tag1 == :method_add_arg and tag2 == :fcall and
            (tag3 == :@ident or tag3 == :@const) and mname == @assertion_method_name and (tag4 == :brace_block or tag4 == :do_block)
          ss.flat_map {|s| extract_idents(s) }
        else
          _, (s0, *) = sexp
          extract_idents(s0)
        end
      when :ifop
        _, s0, s1, s2 = sexp
        [*extract_idents(s0), Branch[extract_idents(s1), extract_idents(s2)]]
      when :if, :unless
        _, s0, ss0, (_, ss1) = sexp
        [*extract_idents(s0), Branch[ss0.flat_map {|s| extract_idents(s) }, ss1 ? ss1.flat_map {|s| extract_idents(s) } : []]]
      when :if_mod, :unless_mod
        _, s0, s1 = sexp
        [*extract_idents(s0), Branch[extract_idents(s1), []]]
      when :var_ref, :var_field
        _, (tag, ref_name, (_, column)) = sexp
        case tag
        when :@kw
          if ref_name == 'self'
            [Ident[:ref, 'self', column]]
          else
            []
          end
        when :@ident, :@const, :@cvar, :@ivar, :@gvar
          [Ident[:ref, ref_name, column]]
        else
          []
        end
      when :@ident, :@const, :@op
        _, method_name, (_, column) = sexp
        [Ident[:method, method_name, column]]
      else
        []
      end
    end

    def str_indices(str, re, offset, limit)
      idx = str.index(re, offset)
      if idx and idx <= limit
        [idx, *str_indices(str, re, idx + 1, limit)]
      else
        []
      end
    end

    MID2SRCTXT = {
      :[] => '[',
      :+@ => '+',
      :-@ => '-',
      :call => '('
    }

    def handle_columnless_ident(left_idents, mid, right_idents, with_safe_op = false)
      left_max = left_idents.flatten.max_by(&:column)
      right_min = right_idents.flatten.min_by(&:column)
      bg = left_max ? left_max.column + left_max.name.length : 0
      ed = right_min ? right_min.column - 1 : @line_for_parsing.length - 1
      mname = mid.to_s
      srctxt = MID2SRCTXT[mid] || mname
      re = /
        #{'\b' if /\A\w/ =~ srctxt}
        #{Regexp.escape(srctxt)}
        #{'\b' if /\w\z/ =~ srctxt}
      /x
      indices = str_indices(@line_for_parsing, re, bg, ed)
      if indices.length == 1 or !(right_idents.empty? and left_idents.empty?)
        ident = Ident[:method, mname, right_idents.empty? ? indices.first : indices.last]
        left_idents + right_idents + (with_safe_op ? [Branch[[ident], []]] : [ident])
      else
        left_idents + right_idents
      end
    end

    def collect_paths(idents, prefixes = [[]], index = 0)
      if index < idents.length
        node = idents[index]
        if node.kind_of?(Branch)
          prefixes = node.flat_map {|n| collect_paths(n, prefixes, 0) }
        else
          prefixes = prefixes.map {|prefix| prefix + [node] }
        end
        collect_paths(idents, prefixes, index + 1)
      else
        prefixes
      end
    end

    class DummyParser < Parser
      def initialize
        super('', nil, nil, TOPLEVEL_BINDING)
      end

      def idents
        []
      end

      def call_paths
        []
      end
    end
    DUMMY = DummyParser.new
  end
  private_constant :Parser
end
