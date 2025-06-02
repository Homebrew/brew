module TypeProf
  class ISeq
    # https://github.com/ruby/ruby/pull/4468
    CASE_WHEN_CHECKMATCH = RubyVM::InstructionSequence.compile("case 1; when Integer; end").to_a.last.any? {|insn,| insn == :checkmatch }
    # https://github.com/ruby/ruby/blob/v3_0_2/vm_core.h#L1206
    VM_ENV_DATA_SIZE = 3
    # Check if Ruby 3.1 or later
    RICH_AST = begin RubyVM::AbstractSyntaxTree.parse("1", keep_script_lines: true).node_id; true; rescue; false; end

    FileInfo = Struct.new(
      :node_id2node,
      :definition_table,
      :caller_table,
      :created_iseqs,
    )

    class << self
      def compile(file)
        compile_core(nil, file)
      end

      def compile_str(str, path = nil)
        compile_core(str, path)
      end

      private def compile_core(str, path)
        opt = RubyVM::InstructionSequence.compile_option
        opt[:inline_const_cache] = false
        opt[:peephole_optimization] = false
        opt[:specialized_instruction] = false
        opt[:operands_unification] = false
        opt[:coverage_enabled] = false

        parse_opts = {}
        parse_opts[:keep_script_lines] = true if RICH_AST

        unless defined?(RubyVM::InstructionSequence)
          puts "Currently, TypeProf can work on a Ruby implementation that supports RubyVM::InstructionSequence, such as CRuby."
          exit 1
        end

        if str
          node = RubyVM::AbstractSyntaxTree.parse(str, **parse_opts)
          iseq = RubyVM::InstructionSequence.compile(str, path, **opt)
        else
          node = RubyVM::AbstractSyntaxTree.parse_file(path, **parse_opts)
          iseq = RubyVM::InstructionSequence.compile_file(path, **opt)
        end

        node_id2node = {}
        build_ast_node_id_table(node, node_id2node) if RICH_AST

        file_info = FileInfo.new(node_id2node, CodeRangeTable.new, CodeRangeTable.new, [])
        iseq_rb = new(iseq.to_a, file_info)
        iseq_rb.collect_local_variable_info(file_info) if RICH_AST
        file_info.created_iseqs.each do |iseq|
          iseq.unify_instructions
        end

        return iseq_rb, file_info.definition_table, file_info.caller_table
      end

      private def build_ast_node_id_table(node, tbl = {})
        tbl[node.node_id] = node
        node.children.each do |child|
          build_ast_node_id_table(child, tbl) if child.is_a?(RubyVM::AbstractSyntaxTree::Node)
        end
        tbl
      end

      def code_range_from_node(node)
        CodeRange.new(
          CodeLocation.new(node.first_lineno, node.first_column),
          CodeLocation.new(node.last_lineno, node.last_column),
        )
      end

      def find_node_by_id(node, id)
        node = RubyVM::AbstractSyntaxTree.parse(node) if node.is_a?(String)

        return node if id == node.node_id

        node.children.each do |child|
          if child.is_a?(RubyVM::AbstractSyntaxTree::Node)
            ret = find_node_by_id(child, id)
            return ret if ret
          end
        end

        nil
      end
    end

    Insn = Struct.new(:insn, :operands, :lineno, :code_range, :definitions)
    class Insn
      def check?(insn_cmp, operands_cmp = nil)
        return insn == insn_cmp && (!operands_cmp || operands == operands_cmp)
      end
    end

    ISEQ_FRESH_ID = [0]

    def initialize(iseq, file_info)
      file_info.created_iseqs << self

      @id = (ISEQ_FRESH_ID[0] += 1)

      _magic, _major_version, _minor_version, _format_type, misc,
        @name, @path, @absolute_path, @start_lineno, @type,
        @locals, @fargs_format, catch_table, insns = *iseq

      fl, fc, ll, lc = misc[:code_location]
      @iseq_code_range = CodeRange.new(CodeLocation.new(fl, fc), CodeLocation.new(ll, lc))

      convert_insns(insns, misc[:node_ids] || [], file_info)

      add_body_start_marker(insns)

      add_exception_cont_marker(insns, catch_table)

      labels = create_label_table(insns)

      @insns = setup_insns(insns, labels, file_info)

      @fargs_format[:opt] = @fargs_format[:opt].map {|l| labels[l] } if @fargs_format[:opt]

      @catch_table = []
      catch_table.map do |type, iseq, first, last, cont, stack_depth|
        iseq = iseq ? ISeq.new(iseq, file_info) : nil
        target = labels[cont]
        entry = [type, iseq, target, stack_depth]
        labels[first].upto(labels[last]) do |i|
          @catch_table[i] ||= []
          @catch_table[i] << entry
        end
      end

      def_node_id = misc[:def_node_id]
      if def_node_id && file_info.node_id2node[def_node_id] && (@type == :method || @type == :block)
        def_node = file_info.node_id2node[def_node_id]
        method_name_token_range = extract_method_name_token_range(def_node)
        if method_name_token_range
          @callers = Utils::MutableSet.new
          file_info.caller_table[method_name_token_range] = @callers
        end
      end

      rename_insn_types
    end

    def extract_method_name_token_range(node)
      case @type
      when :method
        regex = if node.type == :DEFS
           /^def\s+(?:\w+)\s*\.\s*(\w+)/
        else
          /^def\s+(\w+)/
        end
        return nil unless node.source =~ regex
        zero_loc = CodeLocation.new(1, 0)
        name_start = $~.begin(1)
        name_length = $~.end(1) - name_start
        name_head_loc = zero_loc.advance_cursor(name_start, node.source)
        name_tail_loc = name_head_loc.advance_cursor(name_length, node.source)
        return CodeRange.new(
          CodeLocation.new(
            node.first_lineno + (name_head_loc.lineno - 1),
            name_head_loc.lineno == 1 ? node.first_column + name_head_loc.column : name_head_loc.column
          ),
          CodeLocation.new(
            node.first_lineno + (name_tail_loc.lineno - 1),
            name_tail_loc.lineno == 1 ? node.first_column + name_tail_loc.column : name_tail_loc.column
          ),
        )
      when :block
        return ISeq.code_range_from_node(node)
      end
    end

    def source_location(pc)
      "#{ @path }:#{ @insns[pc].lineno }"
    end

    def detailed_source_location(pc)
      code_range = @insns[pc].code_range
      if code_range
        [@path, code_range]
      else
        [@path]
      end
    end

    def add_called_iseq(pc, callee_iseq)
      if callee_iseq && @insns[pc].definitions
        @insns[pc].definitions << [callee_iseq.path, callee_iseq.iseq_code_range]
      end
      if callee_iseq.callers
        callee_iseq.callers << [@path, @insns[pc].code_range]
      end
    end

    def add_def_loc(pc, detailed_loc)
      if detailed_loc && @insns[pc].definitions
        @insns[pc].definitions << detailed_loc
      end
    end

    attr_reader :name, :path, :absolute_path, :start_lineno, :type, :locals, :fargs_format, :catch_table, :insns
    attr_reader :id, :iseq_code_range, :callers

    def pretty_print(q)
      q.text "ISeq["
      q.group do
        q.nest(1) do
          q.breakable ""
          q.text "@type=          #{ @type }"
          q.breakable ", "
          q.text "@name=          #{ @name }"
          q.breakable ", "
          q.text "@path=          #{ @path }"
          q.breakable ", "
          q.text "@absolute_path= #{ @absolute_path }"
          q.breakable ", "
          q.text "@start_lineno=  #{ @start_lineno }"
          q.breakable ", "
          q.text "@fargs_format=  #{ @fargs_format.inspect }"
          q.breakable ", "
          q.text "@insns="
          q.group(2) do
            @insns.each_with_index do |(insn, *operands), i|
              q.breakable
              q.group(2, "#{ i }: #{ insn.to_s }", "") do
                q.pp operands
              end
            end
          end
        end
        q.breakable
      end
      q.text "]"
    end

    def <=>(other)
      @id <=> other.id
    end

    # Remove lineno entry and convert instructions to Insn instances
    def convert_insns(insns, node_ids, file_info)
      ninsns = []
      lineno = 0
      insns.each do |e|
        case e
        when Integer # lineno
          lineno = e
        when Symbol # label or trace
          ninsns << e
        when Array
          insn, *operands = e
          node_id = node_ids.shift
          node = file_info.node_id2node[node_id]
          if node
            code_range = ISeq.code_range_from_node(node)
            case insn
            when :send, :invokesuper
              opt, blk_iseq = operands
              opt[:node_id] = node_id
              if blk_iseq
                misc = blk_iseq[4] # iseq's "misc" field
                misc[:def_node_id] = node_id
              end
            when :definemethod, :definesmethod
              iseq = operands[1]
              misc = iseq[4] # iseq's "misc" field
              misc[:def_node_id] = node_id
            end
          end
          ninsns << Insn.new(insn, operands, lineno, code_range, nil)
        else
          raise "unknown iseq entry: #{ e }"
        end
      end
      insns.replace(ninsns)
    end

    # Insert a dummy instruction "_iseq_body_start"
    def add_body_start_marker(insns)
      case @type
      when :method, :block
        # skip initialization code of optional arguments
        if @fargs_format[:opt]
          label = @fargs_format[:opt].last
          i = insns.index(label) + 1
        else
          i = insns.find_index {|insn| insn.is_a?(Insn) }
        end

        # skip initialization code of keyword arguments
        while insns[i][0] == :checkkeyword
          raise if insns[i + 1].insn != :branchif
          label = insns[i + 1].operands[0]
          i = insns.index(label) + 1
        end

        insns.insert(i, Insn.new(:_iseq_body_start, [], @start_lineno, nil, nil))
      end
    end

    # Insert "nop" instruction to continuation point of exception handlers
    def add_exception_cont_marker(insns, catch_table)
      # rescue/ensure clauses need to have a dedicated return addresses
      # because they requires to be virtually called.
      # So, this preprocess adds "nop" to make a new insn for their return addresses
      exception_cont_labels = {}
      catch_table.map! do |type, iseq, first, last, cont, stack_depth|
        if type == :rescue || type == :ensure
          exception_cont_labels[cont] = true
          cont = :"#{ cont }_exception_cont"
        end
        [type, iseq, first, last, cont, stack_depth]
      end

      i = 0
      while i < insns.size
        e = insns[i]
        if exception_cont_labels[e]
          insns.insert(i, :"#{ e }_exception_cont", Insn.new(:nop, []))
          i += 2
        end
        i += 1
      end
    end

    def create_label_table(insns)
      pc = 0
      labels = {}
      insns.each do |e|
        if e.is_a?(Symbol)
          labels[e] = pc
        else
          pc += 1
        end
      end
      labels
    end

    def setup_insns(insns, labels, file_info)
      ninsns = []
      insns.each do |e|
        case e
        when Symbol # label or trace
          nil
        when Insn
          operands = (INSN_TABLE[e.insn] || []).zip(e.operands).map do |type, operand|
            case type
            when "ISEQ"
              operand && ISeq.new(operand, file_info)
            when "lindex_t", "rb_num_t", "VALUE", "ID", "GENTRY", "CALL_DATA"
              operand
            when "OFFSET"
              labels[operand] || raise("unknown label: #{ operand }")
            when "IVC", "ISE"
              raise unless operand.is_a?(Integer)
              :_cache_operand
            else
              raise "unknown operand type: #{ type }"
            end
          end

          if e.code_range && should_collect_defs(e.insn)
            definition = Utils::MutableSet.new
            file_info.definition_table[e.code_range] = definition
          end

          ninsns << Insn.new(e.insn, operands, e.lineno, e.code_range, definition)
        else
          raise "unknown iseq entry: #{ e }"
        end
      end
      ninsns
    end

    def should_collect_defs(insn_kind)
      case insn_kind
      when :send, :getinstancevariable, :getconstant
        return true
      else
        return false
      end
    end

    # Collect local variable use and definition info recursively
    def collect_local_variable_info(file_info, absolute_level = 0, parent_variable_tables = {})
      # e.g.
      # variable_tables[abs_level][idx] = [[path, code_range]]
      current_variables = []
      variable_tables = parent_variable_tables.merge({
        absolute_level => current_variables
      })

      dummy_def_range = CodeRange.new(
        CodeLocation.new(@start_lineno, 0),
        CodeLocation.new(@start_lineno, 1),
      )
      # Fill tail elements with parameters
      (@fargs_format[:lead_num] || 0).times do |offset|
        current_variables[VM_ENV_DATA_SIZE + @locals.length - offset - 1] ||= Utils::MutableSet.new
        current_variables[VM_ENV_DATA_SIZE + @locals.length - offset - 1] << [@path, dummy_def_range]
      end

      @insns.each do |insn|
        next unless insn.insn == :getlocal || insn.insn == :setlocal

        idx = insn.operands[0]
        # note: level is relative value to the current level
        level = insn.operands[1]
        target_abs_level = absolute_level - level
        variable_tables[target_abs_level] ||= {}
        variable_tables[target_abs_level][idx] ||= Utils::MutableSet.new

        case insn.insn
        when :setlocal
          variable_tables[target_abs_level][idx] << [path, insn.code_range]
        when :getlocal
          file_info.definition_table[insn.code_range] = variable_tables[target_abs_level][idx]
        end
      end

      @insns.each do |insn|
        insn.operands.each do |operand|
          next unless operand.is_a?(ISeq)
          operand.collect_local_variable_info(
            file_info, absolute_level + 1,
            variable_tables
          )
        end
      end
    end

    def rename_insn_types
      @insns.each do |insn|
        case insn.insn
        when :branchif
          insn.insn, insn.operands = :branch, [:if] + insn.operands
        when :branchunless
          insn.insn, insn.operands = :branch, [:unless] + insn.operands
        when :branchnil
          insn.insn, insn.operands = :branch, [:nil] + insn.operands
        when :getblockparam, :getblockparamproxy
          insn.insn = :getlocal
        end
      end
    end

    # Unify some instructions for flow-sensitive analysis
    def unify_instructions
      # This method rewrites instructions to enable flow-sensitive analysis.
      #
      # Consider `if x; ...; else; ... end`.
      # When the variable `x` is of type "Integer | nil",
      # we want to make sure that `x` is "Integer" in then clause.
      # So, we need to split the environment to two ones:
      # one is that `x` is of type "Integer", and the other is that
      # `x` is type "nil".
      #
      # However, `if x` is compiled to "getlocal; branch".
      # TypeProf evaluates them as follows:
      #
      # * "getlocal" pushes the value of `x` to the stack, amd
      # * "branch" checks the value on the top of the stack
      #
      # TypeProf does not keep where the value comes from, so
      # it is difficult to split the environment when evaluating "branch".
      #
      # This method rewrites "getlocal; branch" to "nop; getlocal_branch".
      # The two instructions are unified to "getlocal_branch" instruction,
      # so TypeProf can split the environment.
      #
      # This is a very fragile appoach because it highly depends on the compiler of Ruby.

      # gather branch targets
      # TODO: catch_table should be also considered
      branch_targets = {}
      @insns.each do |insn|
        case insn.insn
        when :branch
          branch_targets[insn.operands[1]] = true
        when :jump
          branch_targets[insn.operands[0]] = true
        end
      end

      # flow-sensitive analysis for `case var; when A; when B; when C; end`
      # find a pattern: getlocal, (dup, putobject(true), getconstant(class name), checkmatch, branch)* for ..Ruby 3.0
      # find a pattern: getlocal, (putobject(true), getconstant(class name), top(1), send(===), branch)* for Ruby 3.1..
      case_branch_list = []
      if CASE_WHEN_CHECKMATCH
        (@insns.size - 1).times do |i|
          insn = @insns[i]
          next unless insn.insn == :getlocal && insn.operands[1] == 0
          getlocal_operands = insn.operands
          nops = [i]
          new_insns = []
          j = i + 1
          while true
            case @insns[j].insn
            when :dup
              break unless @insns[j + 1].check?(:putnil, [])
              break unless @insns[j + 2].check?(:putobject, [true])
              break unless @insns[j + 3].check?(:getconstant) # TODO: support A::B::C
              break unless @insns[j + 4].check?(:checkmatch, [2])
              break unless @insns[j + 5].check?(:branch)
              target_pc = @insns[j + 5].operands[1]
              break unless @insns[target_pc].check?(:pop, [])
              nops << j << (j + 4) << target_pc
              branch_operands = @insns[j + 5][1]
              new_insns << [j + 5, Insn.new(:getlocal_checkmatch_branch, [getlocal_operands, branch_operands])]
              j += 6
            when :pop
              nops << j
              case_branch_list << [nops, new_insns]
              break
            else
              break
            end
          end
        end
      else
        (@insns.size - 1).times do |i|
          insn = @insns[i]
          next unless insn.insn == :getlocal && insn.operands[1] == 0
          getlocal_operands = insn.operands
          nops = []
          new_insns = []
          j = i + 1
          while true
            insn = @insns[j]
            if insn.check?(:putnil, [])
              break unless @insns[j + 1].check?(:putobject, [true])
              break unless @insns[j + 2].check?(:getconstant) # TODO: support A::B::C
              break unless @insns[j + 3].check?(:topn, [1])
              break unless @insns[j + 4].check?(:send) && @insns[j + 4].operands[0].slice(:mid, :flag, :orig_argc) == {:mid=>:===, :flag=>20, :orig_argc=>1}
              break unless @insns[j + 5].check?(:branch)
              target_pc = @insns[j + 5].operands[1]
              break unless @insns[target_pc].check?(:pop, [])
              nops << (j + 4) #<< target_pc
              send_operands = @insns[j + 4][1]
              branch_operands = @insns[j + 5][1]
              new_insns << [j + 5, Insn.new(:arg_getlocal_send_branch, [getlocal_operands, send_operands, branch_operands])]
              j += 6
            elsif insn.check?(:pop, [])
              #nops << j
              case_branch_list << [nops, new_insns]
              break
            else
              break
            end
          end
        end
      end
      case_branch_list.each do |nops, new_insns|
        nops.each {|i| @insns[i] = Insn.new(:nop, []) }
        new_insns.each {|i, insn| @insns[i] = insn }
      end

      # find a pattern: getlocal(recv), ..., send (is_a?, respond_to?), branch
      recv_getlocal_send_branch_list = []
      (@insns.size - 1).times do |i|
        insn = @insns[i]
        if insn.insn == :getlocal && insn.operands[1] == 0
          j = i + 1
          sp = 1
          while @insns[j]
            sp = check_send_branch(sp, j)
            if sp == :match
              recv_getlocal_send_branch_list << [i, j]
              break
            end
            break if !sp
            j += 1
          end
        end
      end
      recv_getlocal_send_branch_list.each do |i, j|
        next if (i + 1 .. j + 1).any? {|i| branch_targets[i] }
        getlocal_operands = @insns[i].operands
        send_operands = @insns[j].operands
        branch_operands = @insns[j + 1].operands
        @insns[j] = Insn.new(:nop, [])
        @insns[j + 1] = Insn.new(:recv_getlocal_send_branch, [getlocal_operands, send_operands, branch_operands])
      end

      # find a pattern: getlocal, send (===), branch
      arg_getlocal_send_branch_list = []
      (@insns.size - 1).times do |i|
        insn1 = @insns[i]
        next unless insn1.insn == :getlocal && insn1.operands[1] == 0
        insn2 = @insns[i + 1]
        next unless insn2.insn == :send
        send_operands = insn2.operands[0]
        next unless send_operands[:flag] == 16 && send_operands[:orig_argc] == 1
        insn3 = @insns[i + 2]
        next unless insn3.insn == :branch
        arg_getlocal_send_branch_list << i
      end
      arg_getlocal_send_branch_list.each do |i|
        next if (i .. i + 2).any? {|i| branch_targets[i] }
        getlocal_operands = @insns[i].operands
        send_operands = @insns[i + 1].operands
        branch_operands = @insns[i + 2].operands
        @insns[i + 1] = Insn.new(:nop, [])
        @insns[i + 2] = Insn.new(:arg_getlocal_send_branch, [getlocal_operands, send_operands, branch_operands])
      end

      # find a pattern: send (block_given?), branch
      send_branch_list = []
      (@insns.size - 1).times do |i|
        insn = @insns[i]
        if insn.insn == :send
          insn = @insns[i + 1]
          if insn.insn == :branch
            send_branch_list << i
          end
        end
      end
      send_branch_list.each do |i|
        next if branch_targets[i + 1]
        send_operands = @insns[i].operands
        branch_operands = @insns[i + 1].operands
        @insns[i] = Insn.new(:nop, [])
        @insns[i + 1] = Insn.new(:send_branch, [send_operands, branch_operands])
      end

      # find a pattern: getlocal, dup, branch
      (@insns.size - 2).times do |i|
        next if branch_targets[i + 1] || branch_targets[i + 2]
        insn0 = @insns[i]
        insn1 = @insns[i + 1]
        insn2 = @insns[i + 2]
        if insn0.insn == :getlocal && insn1.insn == :dup && insn2.insn == :branch && insn0.operands[1] == 0
          getlocal_operands = insn0.operands
          dup_operands      = insn1.operands
          branch_operands   = insn2.operands
          @insns[i    ] = Insn.new(:nop, [])
          @insns[i + 1] = Insn.new(:nop, [])
          @insns[i + 2] = Insn.new(:getlocal_dup_branch, [getlocal_operands, dup_operands, branch_operands])
        end
      end

      # find a pattern: dup, setlocal, branch
      (@insns.size - 2).times do |i|
        next if branch_targets[i + 1] || branch_targets[i + 2]
        insn0 = @insns[i]
        insn1 = @insns[i + 1]
        insn2 = @insns[i + 2]
        if insn0.insn == :dup && insn1.insn == :setlocal && insn2.insn == :branch && insn1.operands[1] == 0
          dup_operands      = insn0.operands
          setlocal_operands = insn1.operands
          branch_operands   = insn2.operands
          @insns[i    ] = Insn.new(:nop, [])
          @insns[i + 1] = Insn.new(:nop, [])
          @insns[i + 2] = Insn.new(:dup_setlocal_branch, [dup_operands, setlocal_operands, branch_operands])
        end
      end

      # find a pattern: dup, branch
      (@insns.size - 1).times do |i|
        next if branch_targets[i + 1]
        insn0 = @insns[i]
        insn1 = @insns[i + 1]
        if insn0.insn == :dup && insn1.insn == :branch
          dup_operands    = insn0.operands
          branch_operands = insn1.operands
          @insns[i    ] = Insn.new(:nop, [])
          @insns[i + 1] = Insn.new(:dup_branch, [dup_operands, branch_operands])
        end
      end

      # find a pattern: getlocal, branch
      (@insns.size - 1).times do |i|
        next if branch_targets[i + 1]
        insn0 = @insns[i]
        insn1 = @insns[i + 1]
        if insn0.insn == :getlocal && insn0.operands[1] == 0 && insn1.insn == :branch
          getlocal_operands = insn0.operands
          branch_operands   = insn1.operands
          @insns[i    ] = Insn.new(:nop, [])
          @insns[i + 1] = Insn.new(:getlocal_branch, [getlocal_operands, branch_operands])
        end
      end
    end

    def check_send_branch(sp, j)
      insn = @insns[j]
      operands = insn.operands

      case insn.insn
      when :putspecialobject, :putnil, :putobject, :duparray, :putstring,
           :putself
        sp += 1
      when :newarray, :newarraykwsplat, :newhash, :concatstrings
        len, = operands
        sp =- len
        return nil if sp <= 0
        sp += 1
      when :newhashfromarray
        raise NotImplementedError, "newhashfromarray"
      when :newrange, :tostring, :objtostring, :anytostring
        sp -= 2
        return nil if sp <= 0
        sp += 1
      when :freezestring
        # XXX: should leverage this information?
      when :toregexp
        _regexp_opt, len = operands
        sp -= len
        return nil if sp <= 0
        sp += 1
      when :intern
        sp -= 1
        return nil if sp <= 0
        sp += 1
      when :definemethod, :definesmethod
      when :defineclass
        sp -= 2
      when :send, :invokesuper
        opt, = operands
        _flags = opt[:flag]
        _mid = opt[:mid]
        kw_arg = opt[:kw_arg]
        argc = opt[:orig_argc]
        argc += 1 # receiver
        argc += kw_arg.size if kw_arg
        sp -= argc
        return :match if insn.insn == :send && sp == 0 && @insns[j + 1].insn == :branch
        sp += 1
      when :arg_getlocal_send_branch
        return # not implemented
      when :invokeblock
        opt, = operands
        sp -= opt[:orig_argc]
        return nil if sp <= 0
        sp += 1
      when :invokebuiltin
        raise NotImplementedError
      when :leave, :throw
        return
      when :once
        return # not implemented
      when :branch, :jump
        return # not implemented
      when :setinstancevariable, :setclassvariable, :setglobal
        sp -= 1
      when :setlocal, :setblockparam
        return # conservative
      when :getinstancevariable, :getclassvariable, :getglobal,
           :getlocal, :getblockparam, :getblockparamproxy, :getlocal_checkmatch_branch
        sp += 1
      when :getconstant
        sp -= 2
        return nil if sp <= 0
        sp += 1
      when :setconstant
        sp -= 2
      when :getspecial
        sp += 1
      when :setspecial
        # flip-flop
        raise NotImplementedError, "setspecial"
      when :dup
        sp += 1
      when :duphash
        sp += 1
      when :dupn
        n, = operands
        sp += n
      when :pop
        sp -= 1
      when :swap
        sp -= 2
        return nil if sp <= 0
        sp += 2
      when :reverse
        n, = operands
        sp -= n
        return nil if sp <= 0
        sp += n
      when :defined
        sp -= 1
        return nil if sp <= 0
        sp += 1
      when :checkmatch
        sp -= 2
        return nil if sp <= 0
        sp += 1
      when :checkkeyword
        sp += 1
      when :adjuststack
        n, = operands
        sp -= n
      when :nop
      when :setn
        return nil # not implemented
      when :topn
        sp += 1
      when :splatarray
        sp -= 1
        return nil if sp <= 0
        sp += 1
      when :expandarray
        num, flag = operands
        splat = flag & 1 == 1
        sp -= 1
        return nil if sp <= 0
        sp += num + (splat ? 1 : 0)
      when :concatarray
        sp -= 2
        return nil if sp <= 0
        sp += 1
      when :checktype
        sp -= 1
        return nil if sp <= 0
        sp += 1
      else
        raise "Unknown insn: #{ insn }"
      end

      return nil if sp <= 0
      sp
    end
  end
end
