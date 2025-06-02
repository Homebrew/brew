# frozen_string_literal: true
module RubyVM::RJIT
  class InsnCompiler
    # struct rb_calling_info. Storing flags instead of ci.
    CallingInfo = Struct.new(:argc, :flags, :kwarg, :ci_addr, :send_shift, :block_handler) do
      def kw_splat = flags & C::VM_CALL_KW_SPLAT != 0
    end

    # @param ocb [CodeBlock]
    # @param exit_compiler [RubyVM::RJIT::ExitCompiler]
    def initialize(cb, ocb, exit_compiler)
      @ocb = ocb
      @exit_compiler = exit_compiler

      @cfunc_codegen_table = {}
      register_cfunc_codegen_funcs
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    # @param insn `RubyVM::RJIT::Instruction`
    def compile(jit, ctx, asm, insn)
      asm.incr_counter(:rjit_insns_count)

      stack = ctx.stack_size.times.map do |stack_idx|
        ctx.get_opnd_type(StackOpnd[ctx.stack_size - stack_idx - 1]).type
      end
      locals = jit.iseq.body.local_table_size.times.map do |local_idx|
        (ctx.local_types[local_idx] || Type::Unknown).type
      end

      insn_idx = format('%04d', (jit.pc.to_i - jit.iseq.body.iseq_encoded.to_i) / C.VALUE.size)
      asm.comment("Insn: #{insn_idx} #{insn.name} (stack: [#{stack.join(', ')}], locals: [#{locals.join(', ')}])")

      # 83/102
      case insn.name
      when :nop then nop(jit, ctx, asm)
      when :getlocal then getlocal(jit, ctx, asm)
      when :setlocal then setlocal(jit, ctx, asm)
      when :getblockparam then getblockparam(jit, ctx, asm)
      # setblockparam
      when :getblockparamproxy then getblockparamproxy(jit, ctx, asm)
      when :getspecial then getspecial(jit, ctx, asm)
      # setspecial
      when :getinstancevariable then getinstancevariable(jit, ctx, asm)
      when :setinstancevariable then setinstancevariable(jit, ctx, asm)
      when :getclassvariable then getclassvariable(jit, ctx, asm)
      when :setclassvariable then setclassvariable(jit, ctx, asm)
      when :opt_getconstant_path then opt_getconstant_path(jit, ctx, asm)
      when :getconstant then getconstant(jit, ctx, asm)
      # setconstant
      when :getglobal then getglobal(jit, ctx, asm)
      # setglobal
      when :putnil then putnil(jit, ctx, asm)
      when :putself then putself(jit, ctx, asm)
      when :putobject then putobject(jit, ctx, asm)
      when :putspecialobject then putspecialobject(jit, ctx, asm)
      when :putstring then putstring(jit, ctx, asm)
      when :concatstrings then concatstrings(jit, ctx, asm)
      when :anytostring then anytostring(jit, ctx, asm)
      when :toregexp then toregexp(jit, ctx, asm)
      when :intern then intern(jit, ctx, asm)
      when :newarray then newarray(jit, ctx, asm)
      # newarraykwsplat
      when :duparray then duparray(jit, ctx, asm)
      # duphash
      when :expandarray then expandarray(jit, ctx, asm)
      when :concatarray then concatarray(jit, ctx, asm)
      when :splatarray then splatarray(jit, ctx, asm)
      when :newhash then newhash(jit, ctx, asm)
      when :newrange then newrange(jit, ctx, asm)
      when :pop then pop(jit, ctx, asm)
      when :dup then dup(jit, ctx, asm)
      when :dupn then dupn(jit, ctx, asm)
      when :swap then swap(jit, ctx, asm)
      # opt_reverse
      when :topn then topn(jit, ctx, asm)
      when :setn then setn(jit, ctx, asm)
      when :adjuststack then adjuststack(jit, ctx, asm)
      when :defined then defined(jit, ctx, asm)
      when :definedivar then definedivar(jit, ctx, asm)
      # checkmatch
      when :checkkeyword then checkkeyword(jit, ctx, asm)
      # checktype
      # defineclass
      # definemethod
      # definesmethod
      when :send then send(jit, ctx, asm)
      when :opt_send_without_block then opt_send_without_block(jit, ctx, asm)
      when :objtostring then objtostring(jit, ctx, asm)
      when :opt_str_freeze then opt_str_freeze(jit, ctx, asm)
      when :opt_nil_p then opt_nil_p(jit, ctx, asm)
      # opt_str_uminus
      when :opt_newarray_send then opt_newarray_send(jit, ctx, asm)
      when :invokesuper then invokesuper(jit, ctx, asm)
      when :invokeblock then invokeblock(jit, ctx, asm)
      when :leave then leave(jit, ctx, asm)
      when :throw then throw(jit, ctx, asm)
      when :jump then jump(jit, ctx, asm)
      when :branchif then branchif(jit, ctx, asm)
      when :branchunless then branchunless(jit, ctx, asm)
      when :branchnil then branchnil(jit, ctx, asm)
      # once
      when :opt_case_dispatch then opt_case_dispatch(jit, ctx, asm)
      when :opt_plus then opt_plus(jit, ctx, asm)
      when :opt_minus then opt_minus(jit, ctx, asm)
      when :opt_mult then opt_mult(jit, ctx, asm)
      when :opt_div then opt_div(jit, ctx, asm)
      when :opt_mod then opt_mod(jit, ctx, asm)
      when :opt_eq then opt_eq(jit, ctx, asm)
      when :opt_neq then opt_neq(jit, ctx, asm)
      when :opt_lt then opt_lt(jit, ctx, asm)
      when :opt_le then opt_le(jit, ctx, asm)
      when :opt_gt then opt_gt(jit, ctx, asm)
      when :opt_ge then opt_ge(jit, ctx, asm)
      when :opt_ltlt then opt_ltlt(jit, ctx, asm)
      when :opt_and then opt_and(jit, ctx, asm)
      when :opt_or then opt_or(jit, ctx, asm)
      when :opt_aref then opt_aref(jit, ctx, asm)
      when :opt_aset then opt_aset(jit, ctx, asm)
      # opt_aset_with
      # opt_aref_with
      when :opt_length then opt_length(jit, ctx, asm)
      when :opt_size then opt_size(jit, ctx, asm)
      when :opt_empty_p then opt_empty_p(jit, ctx, asm)
      when :opt_succ then opt_succ(jit, ctx, asm)
      when :opt_not then opt_not(jit, ctx, asm)
      when :opt_regexpmatch2 then opt_regexpmatch2(jit, ctx, asm)
      # invokebuiltin
      when :opt_invokebuiltin_delegate then opt_invokebuiltin_delegate(jit, ctx, asm)
      when :opt_invokebuiltin_delegate_leave then opt_invokebuiltin_delegate_leave(jit, ctx, asm)
      when :getlocal_WC_0 then getlocal_WC_0(jit, ctx, asm)
      when :getlocal_WC_1 then getlocal_WC_1(jit, ctx, asm)
      when :setlocal_WC_0 then setlocal_WC_0(jit, ctx, asm)
      when :setlocal_WC_1 then setlocal_WC_1(jit, ctx, asm)
      when :putobject_INT2FIX_0_ then putobject_INT2FIX_0_(jit, ctx, asm)
      when :putobject_INT2FIX_1_ then putobject_INT2FIX_1_(jit, ctx, asm)
      else CantCompile
      end
    end

    private

    #
    # Insns
    #

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def nop(jit, ctx, asm)
      # Do nothing
      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def getlocal(jit, ctx, asm)
      idx = jit.operand(0)
      level = jit.operand(1)
      jit_getlocal_generic(jit, ctx, asm, idx:, level:)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def getlocal_WC_0(jit, ctx, asm)
      idx = jit.operand(0)
      jit_getlocal_generic(jit, ctx, asm, idx:, level: 0)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def getlocal_WC_1(jit, ctx, asm)
      idx = jit.operand(0)
      jit_getlocal_generic(jit, ctx, asm, idx:, level: 1)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def setlocal(jit, ctx, asm)
      idx = jit.operand(0)
      level = jit.operand(1)
      jit_setlocal_generic(jit, ctx, asm, idx:, level:)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def setlocal_WC_0(jit, ctx, asm)
      idx = jit.operand(0)
      jit_setlocal_generic(jit, ctx, asm, idx:, level: 0)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def setlocal_WC_1(jit, ctx, asm)
      idx = jit.operand(0)
      jit_setlocal_generic(jit, ctx, asm, idx:, level: 1)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def getblockparam(jit, ctx, asm)
      # EP level
      level = jit.operand(1)

      # Save the PC and SP because we might allocate
      jit_prepare_routine_call(jit, ctx, asm)

      # A mirror of the interpreter code. Checking for the case
      # where it's pushing rb_block_param_proxy.
      side_exit = side_exit(jit, ctx)

      # Load environment pointer EP from CFP
      ep_reg = :rax
      jit_get_ep(asm, level, reg: ep_reg)

      # Bail when VM_ENV_FLAGS(ep, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM) is non zero
      # FIXME: This is testing bits in the same place that the WB check is testing.
      # We should combine these at some point
      asm.test([ep_reg, C.VALUE.size * C::VM_ENV_DATA_INDEX_FLAGS], C::VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM)

      # If the frame flag has been modified, then the actual proc value is
      # already in the EP and we should just use the value.
      frame_flag_modified = asm.new_label('frame_flag_modified')
      asm.jnz(frame_flag_modified)

      # This instruction writes the block handler to the EP.  If we need to
      # fire a write barrier for the write, then exit (we'll let the
      # interpreter handle it so it can fire the write barrier).
      # flags & VM_ENV_FLAG_WB_REQUIRED
      asm.test([ep_reg, C.VALUE.size * C::VM_ENV_DATA_INDEX_FLAGS], C::VM_ENV_FLAG_WB_REQUIRED)

      # if (flags & VM_ENV_FLAG_WB_REQUIRED) != 0
      asm.jnz(side_exit)

      # Convert the block handler in to a proc
      # call rb_vm_bh_to_procval(const rb_execution_context_t *ec, VALUE block_handler)
      asm.mov(C_ARGS[0], EC)
      # The block handler for the current frame
      # note, VM_ASSERT(VM_ENV_LOCAL_P(ep))
      asm.mov(C_ARGS[1], [ep_reg, C.VALUE.size * C::VM_ENV_DATA_INDEX_SPECVAL])
      asm.call(C.rb_vm_bh_to_procval)

      # Load environment pointer EP from CFP (again)
      ep_reg = :rcx
      jit_get_ep(asm, level, reg: ep_reg)

      # Write the value at the environment pointer
      idx = jit.operand(0)
      offs = -(C.VALUE.size * idx)
      asm.mov([ep_reg, offs], C_RET);

      # Set the frame modified flag
      asm.mov(:rax, [ep_reg, C.VALUE.size * C::VM_ENV_DATA_INDEX_FLAGS]) # flag_check
      asm.or(:rax, C::VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM) # modified_flag
      asm.mov([ep_reg, C.VALUE.size * C::VM_ENV_DATA_INDEX_FLAGS], :rax)

      asm.write_label(frame_flag_modified)

      # Push the proc on the stack
      stack_ret = ctx.stack_push(Type::Unknown)
      ep_reg = :rax
      jit_get_ep(asm, level, reg: ep_reg)
      asm.mov(:rax, [ep_reg, offs])
      asm.mov(stack_ret, :rax)

      KeepCompiling
    end

    # setblockparam

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def getblockparamproxy(jit, ctx, asm)
      # To get block_handler
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      starting_context = ctx.dup # make a copy for use with jit_chain_guard

      # A mirror of the interpreter code. Checking for the case
      # where it's pushing rb_block_param_proxy.
      side_exit = side_exit(jit, ctx)

      # EP level
      level = jit.operand(1)

      # Peek at the block handler so we can check whether it's nil
      comptime_handler = jit.peek_at_block_handler(level)

      # When a block handler is present, it should always be a GC-guarded
      # pointer (VM_BH_ISEQ_BLOCK_P)
      if comptime_handler != 0 && comptime_handler & 0x3 != 0x1
        asm.incr_counter(:getblockpp_not_gc_guarded)
        return CantCompile
      end

      # Load environment pointer EP from CFP
      ep_reg = :rax
      jit_get_ep(asm, level, reg: ep_reg)

      # Bail when VM_ENV_FLAGS(ep, VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM) is non zero
      asm.test([ep_reg, C.VALUE.size * C::VM_ENV_DATA_INDEX_FLAGS], C::VM_FRAME_FLAG_MODIFIED_BLOCK_PARAM)
      asm.jnz(counted_exit(side_exit, :getblockpp_block_param_modified))

      # Load the block handler for the current frame
      # note, VM_ASSERT(VM_ENV_LOCAL_P(ep))
      block_handler = :rax
      asm.mov(block_handler, [ep_reg, C.VALUE.size * C::VM_ENV_DATA_INDEX_SPECVAL])

      # Specialize compilation for the case where no block handler is present
      if comptime_handler == 0
        # Bail if there is a block handler
        asm.cmp(block_handler, 0)

        jit_chain_guard(:jnz, jit, starting_context, asm, counted_exit(side_exit, :getblockpp_block_handler_none))

        putobject(jit, ctx, asm, val: Qnil)
      else
        # Block handler is a tagged pointer. Look at the tag. 0x03 is from VM_BH_ISEQ_BLOCK_P().
        asm.and(block_handler, 0x3)

        # Bail unless VM_BH_ISEQ_BLOCK_P(bh). This also checks for null.
        asm.cmp(block_handler, 0x1)

        jit_chain_guard(:jnz, jit, starting_context, asm, counted_exit(side_exit, :getblockpp_not_iseq_block))

        # Push rb_block_param_proxy. It's a root, so no need to use jit_mov_gc_ptr.
        top = ctx.stack_push(Type::BlockParamProxy)
        asm.mov(:rax, C.rb_block_param_proxy)
        asm.mov(top, :rax)
      end

      jump_to_next_insn(jit, ctx, asm)

      EndBlock
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def getspecial(jit, ctx, asm)
      # This takes two arguments, key and type
      # key is only used when type == 0
      # A non-zero type determines which type of backref to fetch
      #rb_num_t key = jit.jit_get_arg(0);
      rtype = jit.operand(1)

      if rtype == 0
        # not yet implemented
        return CantCompile;
      elsif rtype & 0x01 != 0
        # Fetch a "special" backref based on a char encoded by shifting by 1

        # Can raise if matchdata uninitialized
        jit_prepare_routine_call(jit, ctx, asm)

        # call rb_backref_get()
        asm.comment('rb_backref_get')
        asm.call(C.rb_backref_get)

        asm.mov(C_ARGS[0], C_RET) # backref
        case [rtype >> 1].pack('c')
        in ?&
          asm.comment("rb_reg_last_match")
          asm.call(C.rb_reg_last_match)
        in ?`
          asm.comment("rb_reg_match_pre")
          asm.call(C.rb_reg_match_pre)
        in ?'
          asm.comment("rb_reg_match_post")
          asm.call(C.rb_reg_match_post)
        in ?+
          asm.comment("rb_reg_match_last")
          asm.call(C.rb_reg_match_last)
        end

        stack_ret = ctx.stack_push(Type::Unknown)
        asm.mov(stack_ret, C_RET)

        KeepCompiling
      else
        # Fetch the N-th match from the last backref based on type shifted by 1

        # Can raise if matchdata uninitialized
        jit_prepare_routine_call(jit, ctx, asm)

        # call rb_backref_get()
        asm.comment('rb_backref_get')
        asm.call(C.rb_backref_get)

        # rb_reg_nth_match((int)(type >> 1), backref);
        asm.comment('rb_reg_nth_match')
        asm.mov(C_ARGS[0], rtype >> 1)
        asm.mov(C_ARGS[1], C_RET) # backref
        asm.call(C.rb_reg_nth_match)

        stack_ret = ctx.stack_push(Type::Unknown)
        asm.mov(stack_ret, C_RET)

        KeepCompiling
      end
    end

    # setspecial

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def getinstancevariable(jit, ctx, asm)
      # Specialize on a compile-time receiver, and split a block for chain guards
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      id = jit.operand(0)
      comptime_obj = jit.peek_at_self

      jit_getivar(jit, ctx, asm, comptime_obj, id, nil, SelfOpnd)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def setinstancevariable(jit, ctx, asm)
      starting_context = ctx.dup # make a copy for use with jit_chain_guard

      # Defer compilation so we can specialize on a runtime `self`
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      ivar_name = jit.operand(0)
      comptime_receiver = jit.peek_at_self

      # If the comptime receiver is frozen, writing an IV will raise an exception
      # and we don't want to JIT code to deal with that situation.
      if C.rb_obj_frozen_p(comptime_receiver)
        asm.incr_counter(:setivar_frozen)
        return CantCompile
      end

      # Check if the comptime receiver is a T_OBJECT
      receiver_t_object = C::BUILTIN_TYPE(comptime_receiver) == C::T_OBJECT

      # If the receiver isn't a T_OBJECT, or uses a custom allocator,
      # then just write out the IV write as a function call.
      # too-complex shapes can't use index access, so we use rb_ivar_get for them too.
      if !receiver_t_object || shape_too_complex?(comptime_receiver) || ctx.chain_depth >= 10
        asm.comment('call rb_vm_setinstancevariable')

        ic = jit.operand(1)

        # The function could raise exceptions.
        # Note that this modifies REG_SP, which is why we do it first
        jit_prepare_routine_call(jit, ctx, asm)

        # Get the operands from the stack
        val_opnd = ctx.stack_pop(1)

        # Call rb_vm_setinstancevariable(iseq, obj, id, val, ic);
        asm.mov(:rdi, jit.iseq.to_i)
        asm.mov(:rsi, [CFP, C.rb_control_frame_t.offsetof(:self)])
        asm.mov(:rdx, ivar_name)
        asm.mov(:rcx, val_opnd)
        asm.mov(:r8, ic)
        asm.call(C.rb_vm_setinstancevariable)
      else
        # Get the iv index
        shape_id = C.rb_shape_get_shape_id(comptime_receiver)
        ivar_index = C.rb_shape_get_iv_index(shape_id, ivar_name)

        # Get the receiver
        asm.mov(:rax, [CFP, C.rb_control_frame_t.offsetof(:self)])

        # Generate a side exit
        side_exit = side_exit(jit, ctx)

        # Upgrade type
        guard_object_is_heap(jit, ctx, asm, :rax, SelfOpnd, :setivar_not_heap)

        asm.comment('guard shape')
        asm.cmp(DwordPtr[:rax, C.rb_shape_id_offset], shape_id)
        megamorphic_side_exit = counted_exit(side_exit, :setivar_megamorphic)
        jit_chain_guard(:jne, jit, starting_context, asm, megamorphic_side_exit)

        # If we don't have an instance variable index, then we need to
        # transition out of the current shape.
        if ivar_index.nil?
          shape = C.rb_shape_get_shape_by_id(shape_id)

          current_capacity = shape.capacity
          dest_shape = C.rb_shape_get_next_no_warnings(shape, comptime_receiver, ivar_name)
          new_shape_id = C.rb_shape_id(dest_shape)

          if new_shape_id == C::OBJ_TOO_COMPLEX_SHAPE_ID
            asm.incr_counter(:setivar_too_complex)
            return CantCompile
          end

          ivar_index = shape.next_iv_index

          # If the new shape has a different capacity, we need to
          # reallocate the object.
          needs_extension = dest_shape.capacity != shape.capacity

          if needs_extension
            # Generate the C call so that runtime code will increase
            # the capacity and set the buffer.
            asm.mov(C_ARGS[0], :rax)
            asm.mov(C_ARGS[1], current_capacity)
            asm.mov(C_ARGS[2], dest_shape.capacity)
            asm.call(C.rb_ensure_iv_list_size)

            # Load the receiver again after the function call
            asm.mov(:rax, [CFP, C.rb_control_frame_t.offsetof(:self)])
          end

          write_val = ctx.stack_pop(1)
          jit_write_iv(asm, comptime_receiver, :rax, :rcx, ivar_index, write_val, needs_extension)

          # Store the new shape
          asm.comment('write shape')
          asm.mov(:rax, [CFP, C.rb_control_frame_t.offsetof(:self)]) # reload after jit_write_iv
          asm.mov(DwordPtr[:rax, C.rb_shape_id_offset], new_shape_id)
        else
          # If the iv index already exists, then we don't need to
          # transition to a new shape.  The reason is because we find
          # the iv index by searching up the shape tree.  If we've
          # made the transition already, then there's no reason to
          # update the shape on the object.  Just set the IV.
          write_val = ctx.stack_pop(1)
          jit_write_iv(asm, comptime_receiver, :rax, :rcx, ivar_index, write_val, false)
        end

        skip_wb = asm.new_label('skip_wb')
        # If the value we're writing is an immediate, we don't need to WB
        asm.test(write_val, C::RUBY_IMMEDIATE_MASK)
        asm.jnz(skip_wb)

        # If the value we're writing is nil or false, we don't need to WB
        asm.cmp(write_val, Qnil)
        asm.jbe(skip_wb)

        asm.comment('write barrier')
        asm.mov(C_ARGS[0], [CFP, C.rb_control_frame_t.offsetof(:self)]) # reload after jit_write_iv
        asm.mov(C_ARGS[1], write_val)
        asm.call(C.rb_gc_writebarrier)

        asm.write_label(skip_wb)
      end

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def getclassvariable(jit, ctx, asm)
      # rb_vm_getclassvariable can raise exceptions.
      jit_prepare_routine_call(jit, ctx, asm)

      asm.mov(C_ARGS[0], [CFP, C.rb_control_frame_t.offsetof(:iseq)])
      asm.mov(C_ARGS[1], CFP)
      asm.mov(C_ARGS[2], jit.operand(0))
      asm.mov(C_ARGS[3], jit.operand(1))
      asm.call(C.rb_vm_getclassvariable)

      top = ctx.stack_push(Type::Unknown)
      asm.mov(top, C_RET)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def setclassvariable(jit, ctx, asm)
      # rb_vm_setclassvariable can raise exceptions.
      jit_prepare_routine_call(jit, ctx, asm)

      asm.mov(C_ARGS[0], [CFP, C.rb_control_frame_t.offsetof(:iseq)])
      asm.mov(C_ARGS[1], CFP)
      asm.mov(C_ARGS[2], jit.operand(0))
      asm.mov(C_ARGS[3], ctx.stack_pop(1))
      asm.mov(C_ARGS[4], jit.operand(1))
      asm.call(C.rb_vm_setclassvariable)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_getconstant_path(jit, ctx, asm)
      # Cut the block for invalidation
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      ic = C.iseq_inline_constant_cache.new(jit.operand(0))
      idlist = ic.segments

      # Make sure there is an exit for this block as the interpreter might want
      # to invalidate this block from rb_rjit_constant_ic_update().
      # For now, we always take an entry exit even if it was a side exit.
      Invariants.ensure_block_entry_exit(jit, cause: 'opt_getconstant_path')

      # See vm_ic_hit_p(). The same conditions are checked in yjit_constant_ic_update().
      ice = ic.entry
      if ice.nil?
        # In this case, leave a block that unconditionally side exits
        # for the interpreter to invalidate.
        asm.incr_counter(:optgetconst_not_cached)
        return CantCompile
      end

      if ice.ic_cref # with cref
        # Cache is keyed on a certain lexical scope. Use the interpreter's cache.
        side_exit = side_exit(jit, ctx)

        # Call function to verify the cache. It doesn't allocate or call methods.
        asm.mov(C_ARGS[0], ic.to_i)
        asm.mov(C_ARGS[1], [CFP, C.rb_control_frame_t.offsetof(:ep)])
        asm.call(C.rb_vm_ic_hit_p)

        # Check the result. SysV only specifies one byte for _Bool return values,
        # so it's important we only check one bit to ignore the higher bits in the register.
        asm.test(C_RET, 1)
        asm.jz(counted_exit(side_exit, :optgetconst_cache_miss))

        asm.mov(:rax, ic.to_i) # inline_cache
        asm.mov(:rax, [:rax, C.iseq_inline_constant_cache.offsetof(:entry)]) # ic_entry
        asm.mov(:rax, [:rax, C.iseq_inline_constant_cache_entry.offsetof(:value)]) # ic_entry_val

        # Push ic->entry->value
        stack_top = ctx.stack_push(Type::Unknown)
        asm.mov(stack_top, :rax)
      else # without cref
        # TODO: implement this
        # Optimize for single ractor mode.
        # if !assume_single_ractor_mode(jit, ocb)
        #   return CantCompile
        # end

        # Invalidate output code on any constant writes associated with
        # constants referenced within the current block.
        Invariants.assume_stable_constant_names(jit, idlist)

        putobject(jit, ctx, asm, val: ice.value)
      end

      jump_to_next_insn(jit, ctx, asm)
      EndBlock
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def getconstant(jit, ctx, asm)
      id = jit.operand(0)

      # vm_get_ev_const can raise exceptions.
      jit_prepare_routine_call(jit, ctx, asm)

      allow_nil_opnd = ctx.stack_pop(1)
      klass_opnd = ctx.stack_pop(1)

      asm.mov(C_ARGS[0], EC)
      asm.mov(C_ARGS[1], klass_opnd)
      asm.mov(C_ARGS[2], id)
      asm.mov(C_ARGS[3], allow_nil_opnd)
      asm.call(C.rb_vm_get_ev_const)

      top = ctx.stack_push(Type::Unknown)
      asm.mov(top, C_RET)

      KeepCompiling
    end

    # setconstant

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def getglobal(jit, ctx, asm)
      gid = jit.operand(0)

      # Save the PC and SP because we might make a Ruby call for warning
      jit_prepare_routine_call(jit, ctx, asm)

      asm.mov(C_ARGS[0], gid)
      asm.call(C.rb_gvar_get)

      top = ctx.stack_push(Type::Unknown)
      asm.mov(top, C_RET)

      KeepCompiling
    end

    # setglobal

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def putnil(jit, ctx, asm)
      putobject(jit, ctx, asm, val: Qnil)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def putself(jit, ctx, asm)
      stack_top = ctx.stack_push_self
      asm.mov(:rax, [CFP, C.rb_control_frame_t.offsetof(:self)])
      asm.mov(stack_top, :rax)
      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def putobject(jit, ctx, asm, val: jit.operand(0))
      # Push it to the stack
      val_type = Type.from(C.to_ruby(val))
      stack_top = ctx.stack_push(val_type)
      if asm.imm32?(val)
        asm.mov(stack_top, val)
      else # 64-bit immediates can't be directly written to memory
        asm.mov(:rax, val)
        asm.mov(stack_top, :rax)
      end

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def putspecialobject(jit, ctx, asm)
      object_type = jit.operand(0)
      if object_type == C::VM_SPECIAL_OBJECT_VMCORE
        stack_top = ctx.stack_push(Type::UnknownHeap)
        asm.mov(:rax, C.rb_mRubyVMFrozenCore)
        asm.mov(stack_top, :rax)
        KeepCompiling
      else
        # TODO: implement for VM_SPECIAL_OBJECT_CBASE and
        # VM_SPECIAL_OBJECT_CONST_BASE
        CantCompile
      end
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def putstring(jit, ctx, asm)
      put_val = jit.operand(0, ruby: true)

      # Save the PC and SP because the callee will allocate
      jit_prepare_routine_call(jit, ctx, asm)

      asm.mov(C_ARGS[0], EC)
      asm.mov(C_ARGS[1], to_value(put_val))
      asm.call(C.rb_ec_str_resurrect)

      stack_top = ctx.stack_push(Type::TString)
      asm.mov(stack_top, C_RET)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def concatstrings(jit, ctx, asm)
      n = jit.operand(0)

      # Save the PC and SP because we are allocating
      jit_prepare_routine_call(jit, ctx, asm)

      asm.lea(:rax, ctx.sp_opnd(-C.VALUE.size * n))

      # call rb_str_concat_literals(size_t n, const VALUE *strings);
      asm.mov(C_ARGS[0], n)
      asm.mov(C_ARGS[1], :rax)
      asm.call(C.rb_str_concat_literals)

      ctx.stack_pop(n)
      stack_ret = ctx.stack_push(Type::TString)
      asm.mov(stack_ret, C_RET)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def anytostring(jit, ctx, asm)
      # Save the PC and SP since we might call #to_s
      jit_prepare_routine_call(jit, ctx, asm)

      str = ctx.stack_pop(1)
      val = ctx.stack_pop(1)

      asm.mov(C_ARGS[0], str)
      asm.mov(C_ARGS[1], val)
      asm.call(C.rb_obj_as_string_result)

      # Push the return value
      stack_ret = ctx.stack_push(Type::TString)
      asm.mov(stack_ret, C_RET)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def toregexp(jit, ctx, asm)
      opt = jit.operand(0, signed: true)
      cnt = jit.operand(1)

      # Save the PC and SP because this allocates an object and could
      # raise an exception.
      jit_prepare_routine_call(jit, ctx, asm)

      asm.lea(:rax, ctx.sp_opnd(-C.VALUE.size * cnt)) # values_ptr
      ctx.stack_pop(cnt)

      asm.mov(C_ARGS[0], 0)
      asm.mov(C_ARGS[1], cnt)
      asm.mov(C_ARGS[2], :rax) # values_ptr
      asm.call(C.rb_ary_tmp_new_from_values)

      # Save the array so we can clear it later
      asm.push(C_RET)
      asm.push(C_RET) # Alignment

      asm.mov(C_ARGS[0], C_RET)
      asm.mov(C_ARGS[1], opt)
      asm.call(C.rb_reg_new_ary)

      # The actual regex is in RAX now.  Pop the temp array from
      # rb_ary_tmp_new_from_values into C arg regs so we can clear it
      asm.pop(:rcx) # Alignment
      asm.pop(:rcx) # ary

      # The value we want to push on the stack is in RAX right now
      stack_ret = ctx.stack_push(Type::UnknownHeap)
      asm.mov(stack_ret, C_RET)

      # Clear the temp array.
      asm.mov(C_ARGS[0], :rcx) # ary
      asm.call(C.rb_ary_clear)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def intern(jit, ctx, asm)
      # Save the PC and SP because we might allocate
      jit_prepare_routine_call(jit, ctx, asm);

      str = ctx.stack_pop(1)
      asm.mov(C_ARGS[0], str)
      asm.call(C.rb_str_intern)

      # Push the return value
      stack_ret = ctx.stack_push(Type::Unknown)
      asm.mov(stack_ret, C_RET)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def newarray(jit, ctx, asm)
      n = jit.operand(0)

      # Save the PC and SP because we are allocating
      jit_prepare_routine_call(jit, ctx, asm)

      # If n is 0, then elts is never going to be read, so we can just pass null
      if n == 0
        values_ptr = 0
      else
        asm.comment('load pointer to array elts')
        offset_magnitude = C.VALUE.size * n
        values_opnd = ctx.sp_opnd(-(offset_magnitude))
        asm.lea(:rax, values_opnd)
        values_ptr = :rax
      end

      # call rb_ec_ary_new_from_values(struct rb_execution_context_struct *ec, long n, const VALUE *elts);
      asm.mov(C_ARGS[0], EC)
      asm.mov(C_ARGS[1], n)
      asm.mov(C_ARGS[2], values_ptr)
      asm.call(C.rb_ec_ary_new_from_values)

      ctx.stack_pop(n)
      stack_ret = ctx.stack_push(Type::TArray)
      asm.mov(stack_ret, C_RET)

      KeepCompiling
    end

    # newarraykwsplat

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def duparray(jit, ctx, asm)
      ary = jit.operand(0)

      # Save the PC and SP because we are allocating
      jit_prepare_routine_call(jit, ctx, asm)

      # call rb_ary_resurrect(VALUE ary);
      asm.comment('call rb_ary_resurrect')
      asm.mov(C_ARGS[0], ary)
      asm.call(C.rb_ary_resurrect)

      stack_ret = ctx.stack_push(Type::TArray)
      asm.mov(stack_ret, C_RET)

      KeepCompiling
    end

    # duphash

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def expandarray(jit, ctx, asm)
      # Both arguments are rb_num_t which is unsigned
      num = jit.operand(0)
      flag = jit.operand(1)

      # If this instruction has the splat flag, then bail out.
      if flag & 0x01 != 0
        asm.incr_counter(:expandarray_splat)
        return CantCompile
      end

      # If this instruction has the postarg flag, then bail out.
      if flag & 0x02 != 0
        asm.incr_counter(:expandarray_postarg)
        return CantCompile
      end

      side_exit = side_exit(jit, ctx)

      array_opnd = ctx.stack_opnd(0)
      array_stack_opnd = StackOpnd[0]

      # num is the number of requested values. If there aren't enough in the
      # array then we're going to push on nils.
      if ctx.get_opnd_type(array_stack_opnd) == Type::Nil
        ctx.stack_pop(1) # pop after using the type info
        # special case for a, b = nil pattern
        # push N nils onto the stack
        num.times do
          push_opnd = ctx.stack_push(Type::Nil)
          asm.mov(push_opnd, Qnil)
        end
        return KeepCompiling
      end

      # Move the array from the stack and check that it's an array.
      asm.mov(:rax, array_opnd)
      guard_object_is_array(jit, ctx, asm, :rax, :rcx, array_stack_opnd, :expandarray_not_array)
      ctx.stack_pop(1) # pop after using the type info

      # If we don't actually want any values, then just return.
      if num == 0
        return KeepCompiling
      end

      jit_array_len(asm, :rax, :rcx)

      # Only handle the case where the number of values in the array is greater
      # than or equal to the number of values requested.
      asm.cmp(:rcx, num)
      asm.jl(counted_exit(side_exit, :expandarray_rhs_too_small))

      # Conditionally load the address of the heap array into REG1.
      # (struct RArray *)(obj)->as.heap.ptr
      #asm.mov(:rax, array_opnd)
      asm.mov(:rcx, [:rax, C.RBasic.offsetof(:flags)])
      asm.test(:rcx, C::RARRAY_EMBED_FLAG);
      asm.mov(:rcx, [:rax, C.RArray.offsetof(:as, :heap, :ptr)])

      # Load the address of the embedded array into REG1.
      # (struct RArray *)(obj)->as.ary
      asm.lea(:rax, [:rax, C.RArray.offsetof(:as, :ary)])

      asm.cmovnz(:rcx, :rax)

      # Loop backward through the array and push each element onto the stack.
      (num - 1).downto(0).each do |i|
        top = ctx.stack_push(Type::Unknown)
        asm.mov(:rax, [:rcx, i * C.VALUE.size])
        asm.mov(top, :rax)
      end

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def concatarray(jit, ctx, asm)
      # Save the PC and SP because the callee may allocate
      # Note that this modifies REG_SP, which is why we do it first
      jit_prepare_routine_call(jit, ctx, asm)

      # Get the operands from the stack
      ary2st_opnd = ctx.stack_pop(1)
      ary1_opnd = ctx.stack_pop(1)

      # Call rb_vm_concat_array(ary1, ary2st)
      asm.mov(C_ARGS[0], ary1_opnd)
      asm.mov(C_ARGS[1], ary2st_opnd)
      asm.call(C.rb_vm_concat_array)

      stack_ret = ctx.stack_push(Type::TArray)
      asm.mov(stack_ret, C_RET)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def splatarray(jit, ctx, asm)
      flag = jit.operand(0)

      # Save the PC and SP because the callee may allocate
      # Note that this modifies REG_SP, which is why we do it first
      jit_prepare_routine_call(jit, ctx, asm)

      # Get the operands from the stack
      ary_opnd = ctx.stack_pop(1)

      # Call rb_vm_splat_array(flag, ary)
      asm.mov(C_ARGS[0], flag)
      asm.mov(C_ARGS[1], ary_opnd)
      asm.call(C.rb_vm_splat_array)

      stack_ret = ctx.stack_push(Type::TArray)
      asm.mov(stack_ret, C_RET)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def newhash(jit, ctx, asm)
      num = jit.operand(0)

      # Save the PC and SP because we are allocating
      jit_prepare_routine_call(jit, ctx, asm)

      if num != 0
        # val = rb_hash_new_with_size(num / 2);
        asm.mov(C_ARGS[0], num / 2)
        asm.call(C.rb_hash_new_with_size)

        # Save the allocated hash as we want to push it after insertion
        asm.push(C_RET)
        asm.push(C_RET) # x86 alignment

        # Get a pointer to the values to insert into the hash
        asm.lea(:rcx, ctx.stack_opnd(num - 1))

        # rb_hash_bulk_insert(num, STACK_ADDR_FROM_TOP(num), val);
        asm.mov(C_ARGS[0], num)
        asm.mov(C_ARGS[1], :rcx)
        asm.mov(C_ARGS[2], C_RET)
        asm.call(C.rb_hash_bulk_insert)

        asm.pop(:rax)
        asm.pop(:rax)

        ctx.stack_pop(num)
        stack_ret = ctx.stack_push(Type::Hash)
        asm.mov(stack_ret, :rax)
      else
        # val = rb_hash_new();
        asm.call(C.rb_hash_new)
        stack_ret = ctx.stack_push(Type::Hash)
        asm.mov(stack_ret, C_RET)
      end

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def newrange(jit, ctx, asm)
      flag = jit.operand(0)

      # rb_range_new() allocates and can raise
      jit_prepare_routine_call(jit, ctx, asm)

      # val = rb_range_new(low, high, (int)flag);
      asm.mov(C_ARGS[0], ctx.stack_opnd(1))
      asm.mov(C_ARGS[1], ctx.stack_opnd(0))
      asm.mov(C_ARGS[2], flag)
      asm.call(C.rb_range_new)

      ctx.stack_pop(2)
      stack_ret = ctx.stack_push(Type::UnknownHeap)
      asm.mov(stack_ret, C_RET)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def pop(jit, ctx, asm)
      ctx.stack_pop
      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def dup(jit, ctx, asm)
      dup_val = ctx.stack_opnd(0)
      mapping, tmp_type = ctx.get_opnd_mapping(StackOpnd[0])

      loc0 = ctx.stack_push_mapping([mapping, tmp_type])
      asm.mov(:rax, dup_val)
      asm.mov(loc0, :rax)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def dupn(jit, ctx, asm)
      n = jit.operand(0)

      # In practice, seems to be only used for n==2
      if n != 2
        return CantCompile
      end

      opnd1 = ctx.stack_opnd(1)
      opnd0 = ctx.stack_opnd(0)

      mapping1 = ctx.get_opnd_mapping(StackOpnd[1])
      mapping0 = ctx.get_opnd_mapping(StackOpnd[0])

      dst1 = ctx.stack_push_mapping(mapping1)
      asm.mov(:rax, opnd1)
      asm.mov(dst1, :rax)

      dst0 = ctx.stack_push_mapping(mapping0)
      asm.mov(:rax, opnd0)
      asm.mov(dst0, :rax)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def swap(jit, ctx, asm)
      stack_swap(jit, ctx, asm, 0, 1)
      KeepCompiling
    end

    # opt_reverse

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def topn(jit, ctx, asm)
      n = jit.operand(0)

      top_n_val = ctx.stack_opnd(n)
      mapping = ctx.get_opnd_mapping(StackOpnd[n])
      loc0 = ctx.stack_push_mapping(mapping)
      asm.mov(:rax, top_n_val)
      asm.mov(loc0, :rax)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def setn(jit, ctx, asm)
      n = jit.operand(0)

      top_val = ctx.stack_pop(0)
      dst_opnd = ctx.stack_opnd(n)
      asm.mov(:rax, top_val)
      asm.mov(dst_opnd, :rax)

      mapping = ctx.get_opnd_mapping(StackOpnd[0])
      ctx.set_opnd_mapping(StackOpnd[n], mapping)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def adjuststack(jit, ctx, asm)
      n = jit.operand(0)
      ctx.stack_pop(n)
      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def defined(jit, ctx, asm)
      op_type = jit.operand(0)
      obj = jit.operand(1, ruby: true)
      pushval = jit.operand(2, ruby: true)

      # Save the PC and SP because the callee may allocate
      # Note that this modifies REG_SP, which is why we do it first
      jit_prepare_routine_call(jit, ctx, asm)

      # Get the operands from the stack
      v_opnd = ctx.stack_pop(1)

      # Call vm_defined(ec, reg_cfp, op_type, obj, v)
      asm.mov(C_ARGS[0], EC)
      asm.mov(C_ARGS[1], CFP)
      asm.mov(C_ARGS[2], op_type)
      asm.mov(C_ARGS[3], to_value(obj))
      asm.mov(C_ARGS[4], v_opnd)
      asm.call(C.rb_vm_defined)

      asm.test(C_RET, 255)
      asm.mov(:rax, Qnil)
      asm.mov(:rcx, to_value(pushval))
      asm.cmovnz(:rax, :rcx)

      # Push the return value onto the stack
      out_type = if C::SPECIAL_CONST_P(pushval)
        Type::UnknownImm
      else
        Type::Unknown
      end
      stack_ret = ctx.stack_push(out_type)
      asm.mov(stack_ret, :rax)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def definedivar(jit, ctx, asm)
      # Defer compilation so we can specialize base on a runtime receiver
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      ivar_name = jit.operand(0)
      # Value that will be pushed on the stack if the ivar is defined. In practice this is always the
      # string "instance-variable". If the ivar is not defined, nil will be pushed instead.
      pushval = jit.operand(2, ruby: true)

      # Get the receiver
      recv = :rcx
      asm.mov(recv, [CFP, C.rb_control_frame_t.offsetof(:self)])

      # Specialize base on compile time values
      comptime_receiver = jit.peek_at_self

      if shape_too_complex?(comptime_receiver)
        # Fall back to calling rb_ivar_defined

        # Save the PC and SP because the callee may allocate
        # Note that this modifies REG_SP, which is why we do it first
        jit_prepare_routine_call(jit, ctx, asm) # clobbers :rax

        # Call rb_ivar_defined(recv, ivar_name)
        asm.mov(C_ARGS[0], recv)
        asm.mov(C_ARGS[1], ivar_name)
        asm.call(C.rb_ivar_defined)

        # if (rb_ivar_defined(recv, ivar_name)) {
        #  val = pushval;
        # }
        asm.test(C_RET, 255)
        asm.mov(:rax, Qnil)
        asm.mov(:rcx, to_value(pushval))
        asm.cmovnz(:rax, :rcx)

        # Push the return value onto the stack
        out_type = C::SPECIAL_CONST_P(pushval) ? Type::UnknownImm : Type::Unknown
        stack_ret = ctx.stack_push(out_type)
        asm.mov(stack_ret, :rax)

        return KeepCompiling
      end

      shape_id = C.rb_shape_get_shape_id(comptime_receiver)
      ivar_exists = C.rb_shape_get_iv_index(shape_id, ivar_name)

      side_exit = side_exit(jit, ctx)

      # Guard heap object (recv_opnd must be used before stack_pop)
      guard_object_is_heap(jit, ctx, asm, recv, SelfOpnd)

      shape_opnd = DwordPtr[recv, C.rb_shape_id_offset]

      asm.comment('guard shape')
      asm.cmp(shape_opnd, shape_id)
      jit_chain_guard(:jne, jit, ctx, asm, side_exit)

      result = ivar_exists ? C.to_value(pushval) : Qnil
      putobject(jit, ctx, asm, val: result)

      # Jump to next instruction. This allows guard chains to share the same successor.
      jump_to_next_insn(jit, ctx, asm)

      return EndBlock
    end

    # checkmatch

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def checkkeyword(jit, ctx, asm)
      # When a keyword is unspecified past index 32, a hash will be used
      # instead. This can only happen in iseqs taking more than 32 keywords.
      if jit.iseq.body.param.keyword.num >= 32
        return CantCompile
      end

      # The EP offset to the undefined bits local
      bits_offset = jit.operand(0)

      # The index of the keyword we want to check
      index = jit.operand(1, signed: true)

      # Load environment pointer EP
      ep_reg = :rax
      jit_get_ep(asm, 0, reg: ep_reg)

      # VALUE kw_bits = *(ep - bits)
      bits_opnd = [ep_reg, C.VALUE.size * -bits_offset]

      # unsigned int b = (unsigned int)FIX2ULONG(kw_bits);
      # if ((b & (0x01 << idx))) {
      #
      # We can skip the FIX2ULONG conversion by shifting the bit we test
      bit_test = 0x01 << (index + 1)
      asm.test(bits_opnd, bit_test)
      asm.mov(:rax, Qfalse)
      asm.mov(:rcx, Qtrue)
      asm.cmovz(:rax, :rcx)

      stack_ret = ctx.stack_push(Type::UnknownImm)
      asm.mov(stack_ret, :rax)

      KeepCompiling
    end

    # checktype
    # defineclass
    # definemethod
    # definesmethod

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def send(jit, ctx, asm)
      # Specialize on a compile-time receiver, and split a block for chain guards
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      cd = C.rb_call_data.new(jit.operand(0))
      blockiseq = jit.operand(1)

      # calling->ci
      mid = C.vm_ci_mid(cd.ci)
      calling = build_calling(ci: cd.ci, block_handler: blockiseq)

      # vm_sendish
      cme, comptime_recv_klass = jit_search_method(jit, ctx, asm, mid, calling)
      if cme == CantCompile
        return CantCompile
      end
      jit_call_general(jit, ctx, asm, mid, calling, cme, comptime_recv_klass)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_send_without_block(jit, ctx, asm, cd: C.rb_call_data.new(jit.operand(0)))
      # Specialize on a compile-time receiver, and split a block for chain guards
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      # calling->ci
      mid = C.vm_ci_mid(cd.ci)
      calling = build_calling(ci: cd.ci, block_handler: C::VM_BLOCK_HANDLER_NONE)

      # vm_sendish
      cme, comptime_recv_klass = jit_search_method(jit, ctx, asm, mid, calling)
      if cme == CantCompile
        return CantCompile
      end
      jit_call_general(jit, ctx, asm, mid, calling, cme, comptime_recv_klass)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def objtostring(jit, ctx, asm)
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      recv = ctx.stack_opnd(0)
      comptime_recv = jit.peek_at_stack(0)

      if C.RB_TYPE_P(comptime_recv, C::RUBY_T_STRING)
        side_exit = side_exit(jit, ctx)

        jit_guard_known_klass(jit, ctx, asm, C.rb_class_of(comptime_recv), recv, StackOpnd[0], comptime_recv, side_exit)
        # No work needed. The string value is already on the top of the stack.
        KeepCompiling
      else
        cd = C.rb_call_data.new(jit.operand(0))
        opt_send_without_block(jit, ctx, asm, cd:)
      end
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_str_freeze(jit, ctx, asm)
      unless Invariants.assume_bop_not_redefined(jit, C::STRING_REDEFINED_OP_FLAG, C::BOP_FREEZE)
        return CantCompile;
      end

      str = jit.operand(0, ruby: true)

      # Push the return value onto the stack
      stack_ret = ctx.stack_push(Type::CString)
      asm.mov(:rax, to_value(str))
      asm.mov(stack_ret, :rax)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_nil_p(jit, ctx, asm)
      opt_send_without_block(jit, ctx, asm)
    end

    # opt_str_uminus

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_newarray_send(jit, ctx, asm)
      type = C.ID2SYM jit.operand(1)

      case type
      when :min then opt_newarray_min(jit, ctx, asm)
      when :max then opt_newarray_max(jit, ctx, asm)
      when :hash then opt_newarray_hash(jit, ctx, asm)
      else
        return CantCompile
      end
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_newarray_min(jit, ctx, asm)
      num = jit.operand(0)

      # Save the PC and SP because we may allocate
      jit_prepare_routine_call(jit, ctx, asm)

      offset_magnitude = C.VALUE.size * num
      values_opnd = ctx.sp_opnd(-offset_magnitude)
      asm.lea(:rax, values_opnd)

      asm.mov(C_ARGS[0], EC)
      asm.mov(C_ARGS[1], num)
      asm.mov(C_ARGS[2], :rax)
      asm.call(C.rb_vm_opt_newarray_min)

      ctx.stack_pop(num)
      stack_ret = ctx.stack_push(Type::Unknown)
      asm.mov(stack_ret, C_RET)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_newarray_max(jit, ctx, asm)
      num = jit.operand(0)

      # Save the PC and SP because we may allocate
      jit_prepare_routine_call(jit, ctx, asm)

      offset_magnitude = C.VALUE.size * num
      values_opnd = ctx.sp_opnd(-offset_magnitude)
      asm.lea(:rax, values_opnd)

      asm.mov(C_ARGS[0], EC)
      asm.mov(C_ARGS[1], num)
      asm.mov(C_ARGS[2], :rax)
      asm.call(C.rb_vm_opt_newarray_max)

      ctx.stack_pop(num)
      stack_ret = ctx.stack_push(Type::Unknown)
      asm.mov(stack_ret, C_RET)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_newarray_hash(jit, ctx, asm)
      num = jit.operand(0)

      # Save the PC and SP because we may allocate
      jit_prepare_routine_call(jit, ctx, asm)

      offset_magnitude = C.VALUE.size * num
      values_opnd = ctx.sp_opnd(-offset_magnitude)
      asm.lea(:rax, values_opnd)

      asm.mov(C_ARGS[0], EC)
      asm.mov(C_ARGS[1], num)
      asm.mov(C_ARGS[2], :rax)
      asm.call(C.rb_vm_opt_newarray_hash)

      ctx.stack_pop(num)
      stack_ret = ctx.stack_push(Type::Unknown)
      asm.mov(stack_ret, C_RET)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def invokesuper(jit, ctx, asm)
      cd = C.rb_call_data.new(jit.operand(0))
      block = jit.operand(1)

      # Defer compilation so we can specialize on class of receiver
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      me = C.rb_vm_frame_method_entry(jit.cfp)
      if me.nil?
        return CantCompile
      end

      # FIXME: We should track and invalidate this block when this cme is invalidated
      current_defined_class = me.defined_class
      mid = me.def.original_id

      if me.to_i != C.rb_callable_method_entry(current_defined_class, me.called_id).to_i
        # Though we likely could generate this call, as we are only concerned
        # with the method entry remaining valid, assume_method_lookup_stable
        # below requires that the method lookup matches as well
        return CantCompile
      end

      # vm_search_normal_superclass
      rbasic_klass = C.to_ruby(C.RBasic.new(C.to_value(current_defined_class)).klass)
      if C::BUILTIN_TYPE(current_defined_class) == C::RUBY_T_ICLASS && C::BUILTIN_TYPE(rbasic_klass) == C::RUBY_T_MODULE && \
          C::FL_TEST_RAW(rbasic_klass, C::RMODULE_IS_REFINEMENT)
        return CantCompile
      end
      comptime_superclass = C.rb_class_get_superclass(C.RCLASS_ORIGIN(current_defined_class))

      ci = cd.ci
      argc = C.vm_ci_argc(ci)

      ci_flags = C.vm_ci_flag(ci)

      # Don't JIT calls that aren't simple
      # Note, not using VM_CALL_ARGS_SIMPLE because sometimes we pass a block.

      if ci_flags & C::VM_CALL_KWARG != 0
        asm.incr_counter(:send_keywords)
        return CantCompile
      end
      if ci_flags & C::VM_CALL_KW_SPLAT != 0
        asm.incr_counter(:send_kw_splat)
        return CantCompile
      end
      if ci_flags & C::VM_CALL_ARGS_BLOCKARG != 0
        asm.incr_counter(:send_block_arg)
        return CantCompile
      end

      # Ensure we haven't rebound this method onto an incompatible class.
      # In the interpreter we try to avoid making this check by performing some
      # cheaper calculations first, but since we specialize on the method entry
      # and so only have to do this once at compile time this is fine to always
      # check and side exit.
      comptime_recv = jit.peek_at_stack(argc)
      unless C.obj_is_kind_of(comptime_recv, current_defined_class)
        return CantCompile
      end

      # Do method lookup
      cme = C.rb_callable_method_entry(comptime_superclass, mid)

      if cme.nil?
        return CantCompile
      end

      # Check that we'll be able to write this method dispatch before generating checks
      cme_def_type = cme.def.type
      if cme_def_type != C::VM_METHOD_TYPE_ISEQ && cme_def_type != C::VM_METHOD_TYPE_CFUNC
        # others unimplemented
        return CantCompile
      end

      asm.comment('guard known me')
      lep_opnd = :rax
      jit_get_lep(jit, asm, reg: lep_opnd)
      ep_me_opnd = [lep_opnd, C.VALUE.size * C::VM_ENV_DATA_INDEX_ME_CREF]

      asm.mov(:rcx, me.to_i)
      asm.cmp(ep_me_opnd, :rcx)
      asm.jne(counted_exit(side_exit(jit, ctx), :invokesuper_me_changed))

      if block == C::VM_BLOCK_HANDLER_NONE
        # Guard no block passed
        # rb_vm_frame_block_handler(GET_EC()->cfp) == VM_BLOCK_HANDLER_NONE
        # note, we assume VM_ASSERT(VM_ENV_LOCAL_P(ep))
        #
        # TODO: this could properly forward the current block handler, but
        # would require changes to gen_send_*
        asm.comment('guard no block given')
        ep_specval_opnd = [lep_opnd, C.VALUE.size * C::VM_ENV_DATA_INDEX_SPECVAL]
        asm.cmp(ep_specval_opnd, C::VM_BLOCK_HANDLER_NONE)
        asm.jne(counted_exit(side_exit(jit, ctx), :invokesuper_block))
      end

      # We need to assume that both our current method entry and the super
      # method entry we invoke remain stable
      Invariants.assume_method_lookup_stable(jit, me)
      Invariants.assume_method_lookup_stable(jit, cme)

      # Method calls may corrupt types
      ctx.clear_local_types

      calling = build_calling(ci:, block_handler: block)
      case cme_def_type
      in C::VM_METHOD_TYPE_ISEQ
        iseq = def_iseq_ptr(cme.def)
        frame_type = C::VM_FRAME_MAGIC_METHOD | C::VM_ENV_FLAG_LOCAL
        jit_call_iseq(jit, ctx, asm, cme, calling, iseq, frame_type:)
      in C::VM_METHOD_TYPE_CFUNC
        jit_call_cfunc(jit, ctx, asm, cme, calling)
      end
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def invokeblock(jit, ctx, asm)
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      # Get call info
      cd = C.rb_call_data.new(jit.operand(0))
      calling = build_calling(ci: cd.ci, block_handler: :captured)

      # Get block_handler
      cfp = jit.cfp
      lep = C.rb_vm_ep_local_ep(cfp.ep)
      comptime_handler = lep[C::VM_ENV_DATA_INDEX_SPECVAL]

      # Handle each block_handler type
      if comptime_handler == C::VM_BLOCK_HANDLER_NONE # no block given
        asm.incr_counter(:invokeblock_none)
        CantCompile
      elsif comptime_handler & 0x3 == 0x1 # VM_BH_ISEQ_BLOCK_P
        asm.comment('get local EP')
        ep_reg = :rax
        jit_get_lep(jit, asm, reg: ep_reg)
        asm.mov(:rax, [ep_reg, C.VALUE.size * C::VM_ENV_DATA_INDEX_SPECVAL]) # block_handler_opnd

        asm.comment('guard block_handler type')
        side_exit = side_exit(jit, ctx)
        asm.mov(:rcx, :rax)
        asm.and(:rcx, 0x3) # block_handler is a tagged pointer
        asm.cmp(:rcx, 0x1) # VM_BH_ISEQ_BLOCK_P
        tag_changed_exit = counted_exit(side_exit, :invokeblock_tag_changed)
        jit_chain_guard(:jne, jit, ctx, asm, tag_changed_exit)

        comptime_captured = C.rb_captured_block.new(comptime_handler & ~0x3)
        comptime_iseq = comptime_captured.code.iseq

        asm.comment('guard known ISEQ')
        asm.and(:rax, ~0x3) # captured
        asm.mov(:rax, [:rax, C.VALUE.size * 2]) # captured->iseq
        asm.mov(:rcx, comptime_iseq.to_i)
        asm.cmp(:rax, :rcx)
        block_changed_exit = counted_exit(side_exit, :invokeblock_iseq_block_changed)
        jit_chain_guard(:jne, jit, ctx, asm, block_changed_exit)

        jit_call_iseq(jit, ctx, asm, nil, calling, comptime_iseq, frame_type: C::VM_FRAME_MAGIC_BLOCK)
      elsif comptime_handler & 0x3 == 0x3 # VM_BH_IFUNC_P
        # We aren't handling CALLER_SETUP_ARG and CALLER_REMOVE_EMPTY_KW_SPLAT yet.
        if calling.flags & C::VM_CALL_ARGS_SPLAT != 0
          asm.incr_counter(:invokeblock_ifunc_args_splat)
          return CantCompile
        end
        if calling.flags & C::VM_CALL_KW_SPLAT != 0
          asm.incr_counter(:invokeblock_ifunc_kw_splat)
          return CantCompile
        end

        asm.comment('get local EP')
        jit_get_lep(jit, asm, reg: :rax)
        asm.mov(:rcx, [:rax, C.VALUE.size * C::VM_ENV_DATA_INDEX_SPECVAL]) # block_handler_opnd

        asm.comment('guard block_handler type');
        side_exit = side_exit(jit, ctx)
        asm.mov(:rax, :rcx) # block_handler_opnd
        asm.and(:rax, 0x3) # tag_opnd: block_handler is a tagged pointer
        asm.cmp(:rax, 0x3) # VM_BH_IFUNC_P
        tag_changed_exit = counted_exit(side_exit, :invokeblock_tag_changed)
        jit_chain_guard(:jne, jit, ctx, asm, tag_changed_exit)

        # The cfunc may not be leaf
        jit_prepare_routine_call(jit, ctx, asm) # clobbers :rax

        asm.comment('call ifunc')
        asm.and(:rcx, ~0x3) # captured_opnd
        asm.lea(:rax, ctx.sp_opnd(-calling.argc * C.VALUE.size)) # argv
        asm.mov(C_ARGS[0], EC)
        asm.mov(C_ARGS[1], :rcx) # captured_opnd
        asm.mov(C_ARGS[2], calling.argc)
        asm.mov(C_ARGS[3], :rax) # argv
        asm.call(C.rb_vm_yield_with_cfunc)

        ctx.stack_pop(calling.argc)
        stack_ret = ctx.stack_push(Type::Unknown)
        asm.mov(stack_ret, C_RET)

        # cfunc calls may corrupt types
        ctx.clear_local_types

        # Share the successor with other chains
        jump_to_next_insn(jit, ctx, asm)
        EndBlock
      elsif symbol?(comptime_handler)
        asm.incr_counter(:invokeblock_symbol)
        CantCompile
      else # Proc
        asm.incr_counter(:invokeblock_proc)
        CantCompile
      end
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def leave(jit, ctx, asm)
      assert_equal(ctx.stack_size, 1)

      jit_check_ints(jit, ctx, asm)

      asm.comment('pop stack frame')
      asm.lea(:rax, [CFP, C.rb_control_frame_t.size])
      asm.mov(CFP, :rax)
      asm.mov([EC, C.rb_execution_context_t.offsetof(:cfp)], :rax)

      # Return a value (for compile_leave_exit)
      ret_opnd = ctx.stack_pop
      asm.mov(:rax, ret_opnd)

      # Set caller's SP and push a value to its stack (for JIT)
      asm.mov(SP, [CFP, C.rb_control_frame_t.offsetof(:sp)]) # Note: SP is in the position after popping a receiver and arguments
      asm.mov([SP], :rax)

      # Jump to cfp->jit_return
      asm.jmp([CFP, -C.rb_control_frame_t.size + C.rb_control_frame_t.offsetof(:jit_return)])

      EndBlock
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def throw(jit, ctx, asm)
      throw_state = jit.operand(0)
      asm.mov(:rcx, ctx.stack_pop(1)) # throwobj

      # THROW_DATA_NEW allocates. Save SP for GC and PC for allocation tracing as
      # well as handling the catch table. However, not using jit_prepare_routine_call
      # since we don't need a patch point for this implementation.
      jit_save_pc(jit, asm) # clobbers rax
      jit_save_sp(ctx, asm)

      # rb_vm_throw verifies it's a valid throw, sets ec->tag->state, and returns throw
      # data, which is throwobj or a vm_throw_data wrapping it. When ec->tag->state is
      # set, JIT code callers will handle the throw with vm_exec_handle_exception.
      asm.mov(C_ARGS[0], EC)
      asm.mov(C_ARGS[1], CFP)
      asm.mov(C_ARGS[2], throw_state)
      # asm.mov(C_ARGS[3], :rcx) # same reg
      asm.call(C.rb_vm_throw)

      asm.comment('exit from throw')
      asm.pop(SP)
      asm.pop(EC)
      asm.pop(CFP)

      # return C_RET as C_RET
      asm.ret
      EndBlock
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jump(jit, ctx, asm)
      # Check for interrupts, but only on backward branches that may create loops
      jump_offset = jit.operand(0, signed: true)
      if jump_offset < 0
        jit_check_ints(jit, ctx, asm)
      end

      pc = jit.pc + C.VALUE.size * (jit.insn.len + jump_offset)
      jit_direct_jump(jit.iseq, pc, ctx, asm)
      EndBlock
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def branchif(jit, ctx, asm)
      # Check for interrupts, but only on backward branches that may create loops
      jump_offset = jit.operand(0, signed: true)
      if jump_offset < 0
        jit_check_ints(jit, ctx, asm)
      end

      # Get the branch target instruction offsets
      next_pc = jit.pc + C.VALUE.size * jit.insn.len
      jump_pc = jit.pc + C.VALUE.size * (jit.insn.len + jump_offset)

      val_type = ctx.get_opnd_type(StackOpnd[0])
      val_opnd = ctx.stack_pop(1)

      if (result = val_type.known_truthy) != nil
        target_pc = result ? jump_pc : next_pc
        jit_direct_jump(jit.iseq, target_pc, ctx, asm)
      else
        # This `test` sets ZF only for Qnil and Qfalse, which let jz jump.
        asm.test(val_opnd, ~Qnil)

        # Set stubs
        branch_stub = BranchStub.new(
          iseq: jit.iseq,
          shape: Default,
          target0: BranchTarget.new(ctx:, pc: jump_pc), # branch target
          target1: BranchTarget.new(ctx:, pc: next_pc), # fallthrough
        )
        branch_stub.target0.address = Assembler.new.then do |ocb_asm|
          @exit_compiler.compile_branch_stub(ctx, ocb_asm, branch_stub, true)
          @ocb.write(ocb_asm)
        end
        branch_stub.target1.address = Assembler.new.then do |ocb_asm|
          @exit_compiler.compile_branch_stub(ctx, ocb_asm, branch_stub, false)
          @ocb.write(ocb_asm)
        end

        # Jump to target0 on jnz
        branch_stub.compile = compile_branchif(branch_stub)
        branch_stub.compile.call(asm)
      end

      EndBlock
    end

    def compile_branchif(branch_stub) # Proc escapes arguments in memory
      proc do |branch_asm|
        branch_asm.comment("branchif #{branch_stub.shape}")
        branch_asm.stub(branch_stub) do
          case branch_stub.shape
          in Default
            branch_asm.jnz(branch_stub.target0.address)
            branch_asm.jmp(branch_stub.target1.address)
          in Next0
            branch_asm.jz(branch_stub.target1.address)
          in Next1
            branch_asm.jnz(branch_stub.target0.address)
          end
        end
      end
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def branchunless(jit, ctx, asm)
      # Check for interrupts, but only on backward branches that may create loops
      jump_offset = jit.operand(0, signed: true)
      if jump_offset < 0
        jit_check_ints(jit, ctx, asm)
      end

      # Get the branch target instruction offsets
      next_pc = jit.pc + C.VALUE.size * jit.insn.len
      jump_pc = jit.pc + C.VALUE.size * (jit.insn.len + jump_offset)

      val_type = ctx.get_opnd_type(StackOpnd[0])
      val_opnd = ctx.stack_pop(1)

      if (result = val_type.known_truthy) != nil
        target_pc = result ? next_pc : jump_pc
        jit_direct_jump(jit.iseq, target_pc, ctx, asm)
      else
        # This `test` sets ZF only for Qnil and Qfalse, which let jz jump.
        asm.test(val_opnd, ~Qnil)

        # Set stubs
        branch_stub = BranchStub.new(
          iseq: jit.iseq,
          shape: Default,
          target0: BranchTarget.new(ctx:, pc: jump_pc), # branch target
          target1: BranchTarget.new(ctx:, pc: next_pc), # fallthrough
        )
        branch_stub.target0.address = Assembler.new.then do |ocb_asm|
          @exit_compiler.compile_branch_stub(ctx, ocb_asm, branch_stub, true)
          @ocb.write(ocb_asm)
        end
        branch_stub.target1.address = Assembler.new.then do |ocb_asm|
          @exit_compiler.compile_branch_stub(ctx, ocb_asm, branch_stub, false)
          @ocb.write(ocb_asm)
        end

        # Jump to target0 on jz
        branch_stub.compile = compile_branchunless(branch_stub)
        branch_stub.compile.call(asm)
      end

      EndBlock
    end

    def compile_branchunless(branch_stub) # Proc escapes arguments in memory
      proc do |branch_asm|
        branch_asm.comment("branchunless #{branch_stub.shape}")
        branch_asm.stub(branch_stub) do
          case branch_stub.shape
          in Default
            branch_asm.jz(branch_stub.target0.address)
            branch_asm.jmp(branch_stub.target1.address)
          in Next0
            branch_asm.jnz(branch_stub.target1.address)
          in Next1
            branch_asm.jz(branch_stub.target0.address)
          end
        end
      end
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def branchnil(jit, ctx, asm)
      # Check for interrupts, but only on backward branches that may create loops
      jump_offset = jit.operand(0, signed: true)
      if jump_offset < 0
        jit_check_ints(jit, ctx, asm)
      end

      # Get the branch target instruction offsets
      next_pc = jit.pc + C.VALUE.size * jit.insn.len
      jump_pc = jit.pc + C.VALUE.size * (jit.insn.len + jump_offset)

      val_type = ctx.get_opnd_type(StackOpnd[0])
      val_opnd = ctx.stack_pop(1)

      if (result = val_type.known_nil) != nil
        target_pc = result ? jump_pc : next_pc
        jit_direct_jump(jit.iseq, target_pc, ctx, asm)
      else
        asm.cmp(val_opnd, Qnil)

        # Set stubs
        branch_stub = BranchStub.new(
          iseq: jit.iseq,
          shape: Default,
          target0: BranchTarget.new(ctx:, pc: jump_pc), # branch target
          target1: BranchTarget.new(ctx:, pc: next_pc), # fallthrough
        )
        branch_stub.target0.address = Assembler.new.then do |ocb_asm|
          @exit_compiler.compile_branch_stub(ctx, ocb_asm, branch_stub, true)
          @ocb.write(ocb_asm)
        end
        branch_stub.target1.address = Assembler.new.then do |ocb_asm|
          @exit_compiler.compile_branch_stub(ctx, ocb_asm, branch_stub, false)
          @ocb.write(ocb_asm)
        end

        # Jump to target0 on je
        branch_stub.compile = compile_branchnil(branch_stub)
        branch_stub.compile.call(asm)
      end

      EndBlock
    end

    def compile_branchnil(branch_stub) # Proc escapes arguments in memory
      proc do |branch_asm|
        branch_asm.comment("branchnil #{branch_stub.shape}")
        branch_asm.stub(branch_stub) do
          case branch_stub.shape
          in Default
            branch_asm.je(branch_stub.target0.address)
            branch_asm.jmp(branch_stub.target1.address)
          in Next0
            branch_asm.jne(branch_stub.target1.address)
          in Next1
            branch_asm.je(branch_stub.target0.address)
          end
        end
      end
    end

    # once

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_case_dispatch(jit, ctx, asm)
      # Normally this instruction would lookup the key in a hash and jump to an
      # offset based on that.
      # Instead we can take the fallback case and continue with the next
      # instruction.
      # We'd hope that our jitted code will be sufficiently fast without the
      # hash lookup, at least for small hashes, but it's worth revisiting this
      # assumption in the future.
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end
      starting_context = ctx.dup

      case_hash = jit.operand(0, ruby: true)
      else_offset = jit.operand(1)

      # Try to reorder case/else branches so that ones that are actually used come first.
      # Supporting only Fixnum for now so that the implementation can be an equality check.
      key_opnd = ctx.stack_pop(1)
      comptime_key = jit.peek_at_stack(0)

      # Check that all cases are fixnums to avoid having to register BOP assumptions on
      # all the types that case hashes support. This spends compile time to save memory.
      if fixnum?(comptime_key) && comptime_key <= 2**32 && C.rb_hash_keys(case_hash).all? { |key| fixnum?(key) }
        unless Invariants.assume_bop_not_redefined(jit, C::INTEGER_REDEFINED_OP_FLAG, C::BOP_EQQ)
          return CantCompile
        end

        # Check if the key is the same value
        asm.cmp(key_opnd, to_value(comptime_key))
        side_exit = side_exit(jit, starting_context)
        jit_chain_guard(:jne, jit, starting_context, asm, side_exit)

        # Get the offset for the compile-time key
        offset = C.rb_hash_stlike_lookup(case_hash, comptime_key)
        # NOTE: If we hit the else branch with various values, it could negatively impact the performance.
        jump_offset = offset || else_offset

        # Jump to the offset of case or else
        target_pc = jit.pc + (jit.insn.len + jump_offset) * C.VALUE.size
        jit_direct_jump(jit.iseq, target_pc, ctx, asm)
        EndBlock
      else
        KeepCompiling # continue with === branches
      end
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_plus(jit, ctx, asm)
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      comptime_recv = jit.peek_at_stack(1)
      comptime_obj  = jit.peek_at_stack(0)

      if fixnum?(comptime_recv) && fixnum?(comptime_obj)
        unless Invariants.assume_bop_not_redefined(jit, C::INTEGER_REDEFINED_OP_FLAG, C::BOP_PLUS)
          return CantCompile
        end

        # Check that both operands are fixnums
        guard_two_fixnums(jit, ctx, asm)

        obj_opnd  = ctx.stack_pop
        recv_opnd = ctx.stack_pop

        asm.mov(:rax, recv_opnd)
        asm.sub(:rax, 1) # untag
        asm.mov(:rcx, obj_opnd)
        asm.add(:rax, :rcx)
        asm.jo(side_exit(jit, ctx))

        dst_opnd = ctx.stack_push(Type::Fixnum)
        asm.mov(dst_opnd, :rax)

        KeepCompiling
      else
        opt_send_without_block(jit, ctx, asm)
      end
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_minus(jit, ctx, asm)
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      comptime_recv = jit.peek_at_stack(1)
      comptime_obj  = jit.peek_at_stack(0)

      if fixnum?(comptime_recv) && fixnum?(comptime_obj)
        unless Invariants.assume_bop_not_redefined(jit, C::INTEGER_REDEFINED_OP_FLAG, C::BOP_MINUS)
          return CantCompile
        end

        # Check that both operands are fixnums
        guard_two_fixnums(jit, ctx, asm)

        obj_opnd  = ctx.stack_pop
        recv_opnd = ctx.stack_pop

        asm.mov(:rax, recv_opnd)
        asm.mov(:rcx, obj_opnd)
        asm.sub(:rax, :rcx)
        asm.jo(side_exit(jit, ctx))
        asm.add(:rax, 1) # re-tag

        dst_opnd = ctx.stack_push(Type::Fixnum)
        asm.mov(dst_opnd, :rax)

        KeepCompiling
      else
        opt_send_without_block(jit, ctx, asm)
      end
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_mult(jit, ctx, asm)
      opt_send_without_block(jit, ctx, asm)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_div(jit, ctx, asm)
      opt_send_without_block(jit, ctx, asm)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_mod(jit, ctx, asm)
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      if two_fixnums_on_stack?(jit)
        unless Invariants.assume_bop_not_redefined(jit, C::INTEGER_REDEFINED_OP_FLAG, C::BOP_MOD)
          return CantCompile
        end

        # Check that both operands are fixnums
        guard_two_fixnums(jit, ctx, asm)

        # Get the operands and destination from the stack
        arg1 = ctx.stack_pop(1)
        arg0 = ctx.stack_pop(1)

        # Check for arg0 % 0
        asm.cmp(arg1, 0)
        asm.je(side_exit(jit, ctx))

        # Call rb_fix_mod_fix(VALUE recv, VALUE obj)
        asm.mov(C_ARGS[0], arg0)
        asm.mov(C_ARGS[1], arg1)
        asm.call(C.rb_fix_mod_fix)

        # Push the return value onto the stack
        stack_ret = ctx.stack_push(Type::Fixnum)
        asm.mov(stack_ret, C_RET)

        KeepCompiling
      else
        opt_send_without_block(jit, ctx, asm)
      end
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_eq(jit, ctx, asm)
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      if jit_equality_specialized(jit, ctx, asm, true)
        jump_to_next_insn(jit, ctx, asm)
        EndBlock
      else
        opt_send_without_block(jit, ctx, asm)
      end
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_neq(jit, ctx, asm)
      # opt_neq is passed two rb_call_data as arguments:
      # first for ==, second for !=
      neq_cd = C.rb_call_data.new(jit.operand(1))
      opt_send_without_block(jit, ctx, asm, cd: neq_cd)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_lt(jit, ctx, asm)
      jit_fixnum_cmp(jit, ctx, asm, opcode: :cmovl, bop: C::BOP_LT)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_le(jit, ctx, asm)
      jit_fixnum_cmp(jit, ctx, asm, opcode: :cmovle, bop: C::BOP_LE)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_gt(jit, ctx, asm)
      jit_fixnum_cmp(jit, ctx, asm, opcode: :cmovg, bop: C::BOP_GT)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_ge(jit, ctx, asm)
      jit_fixnum_cmp(jit, ctx, asm, opcode: :cmovge, bop: C::BOP_GE)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_ltlt(jit, ctx, asm)
      opt_send_without_block(jit, ctx, asm)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_and(jit, ctx, asm)
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      if two_fixnums_on_stack?(jit)
        unless Invariants.assume_bop_not_redefined(jit, C::INTEGER_REDEFINED_OP_FLAG, C::BOP_AND)
          return CantCompile
        end

        # Check that both operands are fixnums
        guard_two_fixnums(jit, ctx, asm)

        # Get the operands and destination from the stack
        arg1 = ctx.stack_pop(1)
        arg0 = ctx.stack_pop(1)

        asm.comment('bitwise and')
        asm.mov(:rax, arg0)
        asm.and(:rax, arg1)

        # Push the return value onto the stack
        dst = ctx.stack_push(Type::Fixnum)
        asm.mov(dst, :rax)

        KeepCompiling
      else
        opt_send_without_block(jit, ctx, asm)
      end
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_or(jit, ctx, asm)
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      if two_fixnums_on_stack?(jit)
        unless Invariants.assume_bop_not_redefined(jit, C::INTEGER_REDEFINED_OP_FLAG, C::BOP_OR)
          return CantCompile
        end

        # Check that both operands are fixnums
        guard_two_fixnums(jit, ctx, asm)

        # Get the operands and destination from the stack
        asm.comment('bitwise or')
        arg1 = ctx.stack_pop(1)
        arg0 = ctx.stack_pop(1)

        # Do the bitwise or arg0 | arg1
        asm.mov(:rax, arg0)
        asm.or(:rax, arg1)

        # Push the return value onto the stack
        dst = ctx.stack_push(Type::Fixnum)
        asm.mov(dst, :rax)

        KeepCompiling
      else
        opt_send_without_block(jit, ctx, asm)
      end
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_aref(jit, ctx, asm)
      cd = C.rb_call_data.new(jit.operand(0))
      argc = C.vm_ci_argc(cd.ci)

      if argc != 1
        asm.incr_counter(:optaref_argc_not_one)
        return CantCompile
      end

      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      comptime_recv = jit.peek_at_stack(1)
      comptime_obj  = jit.peek_at_stack(0)

      side_exit = side_exit(jit, ctx)

      if C.rb_class_of(comptime_recv) == Array && fixnum?(comptime_obj)
        unless Invariants.assume_bop_not_redefined(jit, C::ARRAY_REDEFINED_OP_FLAG, C::BOP_AREF)
          return CantCompile
        end

        idx_opnd = ctx.stack_opnd(0)
        recv_opnd = ctx.stack_opnd(1)

        not_array_exit = counted_exit(side_exit, :optaref_recv_not_array)
        jit_guard_known_klass(jit, ctx, asm, C.rb_class_of(comptime_recv), recv_opnd, StackOpnd[1], comptime_recv, not_array_exit)

        # Bail if idx is not a FIXNUM
        asm.mov(:rax, idx_opnd)
        asm.test(:rax, C::RUBY_FIXNUM_FLAG)
        asm.jz(counted_exit(side_exit, :optaref_arg_not_fixnum))

        # Call VALUE rb_ary_entry_internal(VALUE ary, long offset).
        # It never raises or allocates, so we don't need to write to cfp->pc.
        asm.sar(:rax, 1) # Convert fixnum to int
        asm.mov(C_ARGS[0], recv_opnd)
        asm.mov(C_ARGS[1], :rax)
        asm.call(C.rb_ary_entry_internal)

        # Pop the argument and the receiver
        ctx.stack_pop(2)

        # Push the return value onto the stack
        stack_ret = ctx.stack_push(Type::Unknown)
        asm.mov(stack_ret, C_RET)

        # Let guard chains share the same successor
        jump_to_next_insn(jit, ctx, asm)
        EndBlock
      elsif C.rb_class_of(comptime_recv) == Hash
        unless Invariants.assume_bop_not_redefined(jit, C::HASH_REDEFINED_OP_FLAG, C::BOP_AREF)
          return CantCompile
        end

        recv_opnd = ctx.stack_opnd(1)

        # Guard that the receiver is a Hash
        not_hash_exit = counted_exit(side_exit, :optaref_recv_not_hash)
        jit_guard_known_klass(jit, ctx, asm, C.rb_class_of(comptime_recv), recv_opnd, StackOpnd[1], comptime_recv, not_hash_exit)

        # Prepare to call rb_hash_aref(). It might call #hash on the key.
        jit_prepare_routine_call(jit, ctx, asm)

        asm.comment('call rb_hash_aref')
        key_opnd = ctx.stack_opnd(0)
        recv_opnd = ctx.stack_opnd(1)
        asm.mov(:rdi, recv_opnd)
        asm.mov(:rsi, key_opnd)
        asm.call(C.rb_hash_aref)

        # Pop the key and the receiver
        ctx.stack_pop(2)

        stack_ret = ctx.stack_push(Type::Unknown)
        asm.mov(stack_ret, C_RET)

        # Let guard chains share the same successor
        jump_to_next_insn(jit, ctx, asm)
        EndBlock
      else
        opt_send_without_block(jit, ctx, asm)
      end
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_aset(jit, ctx, asm)
      # Defer compilation so we can specialize on a runtime `self`
      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      comptime_recv = jit.peek_at_stack(2)
      comptime_key = jit.peek_at_stack(1)

      # Get the operands from the stack
      recv = ctx.stack_opnd(2)
      key = ctx.stack_opnd(1)
      _val = ctx.stack_opnd(0)

      if C.rb_class_of(comptime_recv) == Array && fixnum?(comptime_key)
        side_exit = side_exit(jit, ctx)

        # Guard receiver is an Array
        jit_guard_known_klass(jit, ctx, asm, C.rb_class_of(comptime_recv), recv, StackOpnd[2], comptime_recv, side_exit)

        # Guard key is a fixnum
        jit_guard_known_klass(jit, ctx, asm, C.rb_class_of(comptime_key), key, StackOpnd[1], comptime_key, side_exit)

        # We might allocate or raise
        jit_prepare_routine_call(jit, ctx, asm)

        asm.comment('call rb_ary_store')
        recv = ctx.stack_opnd(2)
        key = ctx.stack_opnd(1)
        val = ctx.stack_opnd(0)
        asm.mov(:rax, key)
        asm.sar(:rax, 1) # FIX2LONG(key)
        asm.mov(C_ARGS[0], recv)
        asm.mov(C_ARGS[1], :rax)
        asm.mov(C_ARGS[2], val)
        asm.call(C.rb_ary_store)

        # rb_ary_store returns void
        # stored value should still be on stack
        val = ctx.stack_opnd(0)

        # Push the return value onto the stack
        ctx.stack_pop(3)
        stack_ret = ctx.stack_push(Type::Unknown)
        asm.mov(:rax, val)
        asm.mov(stack_ret, :rax)

        jump_to_next_insn(jit, ctx, asm)
        EndBlock
      elsif C.rb_class_of(comptime_recv) == Hash
        side_exit = side_exit(jit, ctx)

        # Guard receiver is a Hash
        jit_guard_known_klass(jit, ctx, asm, C.rb_class_of(comptime_recv), recv, StackOpnd[2], comptime_recv, side_exit)

        # We might allocate or raise
        jit_prepare_routine_call(jit, ctx, asm)

        # Call rb_hash_aset
        recv = ctx.stack_opnd(2)
        key = ctx.stack_opnd(1)
        val = ctx.stack_opnd(0)
        asm.mov(C_ARGS[0], recv)
        asm.mov(C_ARGS[1], key)
        asm.mov(C_ARGS[2], val)
        asm.call(C.rb_hash_aset)

        # Push the return value onto the stack
        ctx.stack_pop(3)
        stack_ret = ctx.stack_push(Type::Unknown)
        asm.mov(stack_ret, C_RET)

        jump_to_next_insn(jit, ctx, asm)
        EndBlock
      else
        opt_send_without_block(jit, ctx, asm)
      end
    end

    # opt_aset_with
    # opt_aref_with

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_length(jit, ctx, asm)
      opt_send_without_block(jit, ctx, asm)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_size(jit, ctx, asm)
      opt_send_without_block(jit, ctx, asm)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_empty_p(jit, ctx, asm)
      opt_send_without_block(jit, ctx, asm)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_succ(jit, ctx, asm)
      opt_send_without_block(jit, ctx, asm)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_not(jit, ctx, asm)
      opt_send_without_block(jit, ctx, asm)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_regexpmatch2(jit, ctx, asm)
      opt_send_without_block(jit, ctx, asm)
    end

    # invokebuiltin

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_invokebuiltin_delegate(jit, ctx, asm)
      bf = C.rb_builtin_function.new(jit.operand(0))
      bf_argc = bf.argc
      start_index = jit.operand(1)

      # ec, self, and arguments
      if bf_argc + 2 > C_ARGS.size
        return CantCompile
      end

      # If the calls don't allocate, do they need up to date PC, SP?
      jit_prepare_routine_call(jit, ctx, asm)

      # Call the builtin func (ec, recv, arg1, arg2, ...)
      asm.comment('call builtin func')
      asm.mov(C_ARGS[0], EC)
      asm.mov(C_ARGS[1], [CFP, C.rb_control_frame_t.offsetof(:self)])

      # Copy arguments from locals
      if bf_argc > 0
        # Load environment pointer EP from CFP
        asm.mov(:rax, [CFP, C.rb_control_frame_t.offsetof(:ep)])

        bf_argc.times do |i|
          table_size = jit.iseq.body.local_table_size
          offs = -table_size - C::VM_ENV_DATA_SIZE + 1 + start_index + i
          asm.mov(C_ARGS[2 + i], [:rax, offs * C.VALUE.size])
        end
      end
      asm.call(bf.func_ptr)

      # Push the return value
      stack_ret = ctx.stack_push(Type::Unknown)
      asm.mov(stack_ret, C_RET)

      KeepCompiling
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def opt_invokebuiltin_delegate_leave(jit, ctx, asm)
      opt_invokebuiltin_delegate(jit, ctx, asm)
      # opt_invokebuiltin_delegate is always followed by leave insn
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def putobject_INT2FIX_0_(jit, ctx, asm)
      putobject(jit, ctx, asm, val: C.to_value(0))
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def putobject_INT2FIX_1_(jit, ctx, asm)
      putobject(jit, ctx, asm, val: C.to_value(1))
    end

    #
    # C func
    #

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_true(jit, ctx, asm, argc, _known_recv_class)
      return false if argc != 0
      asm.comment('nil? == true')
      ctx.stack_pop(1)
      stack_ret = ctx.stack_push(Type::True)
      asm.mov(stack_ret, Qtrue)
      true
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_false(jit, ctx, asm, argc, _known_recv_class)
      return false if argc != 0
      asm.comment('nil? == false')
      ctx.stack_pop(1)
      stack_ret = ctx.stack_push(Type::False)
      asm.mov(stack_ret, Qfalse)
      true
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_kernel_is_a(jit, ctx, asm, argc, known_recv_class)
      if argc != 1
        return false
      end

      # If this is a super call we might not know the class
      if known_recv_class.nil?
        return false
      end

      # Important note: The output code will simply `return true/false`.
      # Correctness follows from:
      #  - `known_recv_class` implies there is a guard scheduled before here
      #    for a particular `CLASS_OF(lhs)`.
      #  - We guard that rhs is identical to the compile-time sample
      #  - In general, for any two Class instances A, B, `A < B` does not change at runtime.
      #    Class#superclass is stable.

      sample_rhs = jit.peek_at_stack(0)
      sample_lhs = jit.peek_at_stack(1)

      # We are not allowing module here because the module hierarchy can change at runtime.
      if C.RB_TYPE_P(sample_rhs, C::RUBY_T_CLASS)
        return false
      end
      sample_is_a = C.obj_is_kind_of(sample_lhs, sample_rhs)

      side_exit = side_exit(jit, ctx)
      asm.comment('Kernel#is_a?')
      asm.mov(:rax, to_value(sample_rhs))
      asm.cmp(ctx.stack_opnd(0), :rax)
      asm.jne(counted_exit(side_exit, :send_is_a_class_mismatch))

      ctx.stack_pop(2)

      if sample_is_a
        stack_ret = ctx.stack_push(Type::True)
        asm.mov(stack_ret, Qtrue)
      else
        stack_ret = ctx.stack_push(Type::False)
        asm.mov(stack_ret, Qfalse)
      end
      return true
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_kernel_instance_of(jit, ctx, asm, argc, known_recv_class)
      if argc != 1
        return false
      end

      # If this is a super call we might not know the class
      if known_recv_class.nil?
        return false
      end

      # Important note: The output code will simply `return true/false`.
      # Correctness follows from:
      #  - `known_recv_class` implies there is a guard scheduled before here
      #    for a particular `CLASS_OF(lhs)`.
      #  - We guard that rhs is identical to the compile-time sample
      #  - For a particular `CLASS_OF(lhs)`, `rb_obj_class(lhs)` does not change.
      #    (because for any singleton class `s`, `s.superclass.equal?(s.attached_object.class)`)

      sample_rhs = jit.peek_at_stack(0)
      sample_lhs = jit.peek_at_stack(1)

      # Filters out cases where the C implementation raises
      unless C.RB_TYPE_P(sample_rhs, C::RUBY_T_CLASS) || C.RB_TYPE_P(sample_rhs, C::RUBY_T_MODULE)
        return false
      end

      # We need to grab the class here to deal with singleton classes.
      # Instance of grabs the "real class" of the object rather than the
      # singleton class.
      sample_lhs_real_class = C.rb_obj_class(sample_lhs)

      sample_instance_of = (sample_lhs_real_class == sample_rhs)

      side_exit = side_exit(jit, ctx)
      asm.comment('Kernel#instance_of?')
      asm.mov(:rax, to_value(sample_rhs))
      asm.cmp(ctx.stack_opnd(0), :rax)
      asm.jne(counted_exit(side_exit, :send_instance_of_class_mismatch))

      ctx.stack_pop(2)

      if sample_instance_of
        stack_ret = ctx.stack_push(Type::True)
        asm.mov(stack_ret, Qtrue)
      else
        stack_ret = ctx.stack_push(Type::False)
        asm.mov(stack_ret, Qfalse)
      end
      return true;
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_obj_not(jit, ctx, asm, argc, _known_recv_class)
      return false if argc != 0
      recv_type = ctx.get_opnd_type(StackOpnd[0])

      case recv_type.known_truthy
      in false
        asm.comment('rb_obj_not(nil_or_false)')
        ctx.stack_pop(1)
        out_opnd = ctx.stack_push(Type::True)
        asm.mov(out_opnd, Qtrue)
      in true
        # Note: recv_type != Type::Nil && recv_type != Type::False.
        asm.comment('rb_obj_not(truthy)')
        ctx.stack_pop(1)
        out_opnd = ctx.stack_push(Type::False)
        asm.mov(out_opnd, Qfalse)
      in nil
        asm.comment('rb_obj_not')

        recv = ctx.stack_pop
        # This `test` sets ZF only for Qnil and Qfalse, which let cmovz set.
        asm.test(recv, ~Qnil)
        asm.mov(:rax, Qfalse)
        asm.mov(:rcx, Qtrue)
        asm.cmovz(:rax, :rcx)

        stack_ret = ctx.stack_push(Type::UnknownImm)
        asm.mov(stack_ret, :rax)
      end
      true
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_obj_equal(jit, ctx, asm, argc, _known_recv_class)
      return false if argc != 1
      asm.comment('equal?')
      obj1 = ctx.stack_pop(1)
      obj2 = ctx.stack_pop(1)

      asm.mov(:rax, obj1)
      asm.mov(:rcx, obj2)
      asm.cmp(:rax, :rcx)
      asm.mov(:rax, Qfalse)
      asm.mov(:rcx, Qtrue)
      asm.cmove(:rax, :rcx)

      stack_ret = ctx.stack_push(Type::UnknownImm)
      asm.mov(stack_ret, :rax)
      true
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_obj_not_equal(jit, ctx, asm, argc, _known_recv_class)
      return false if argc != 1
      jit_equality_specialized(jit, ctx, asm, false)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_mod_eqq(jit, ctx, asm, argc, _known_recv_class)
      return false if argc != 1

      asm.comment('Module#===')
      # By being here, we know that the receiver is a T_MODULE or a T_CLASS, because Module#=== can
      # only live on these objects. With that, we can call rb_obj_is_kind_of() without
      # jit_prepare_routine_call() or a control frame push because it can't raise, allocate, or call
      # Ruby methods with these inputs.
      # Note the difference in approach from Kernel#is_a? because we don't get a free guard for the
      # right hand side.
      lhs = ctx.stack_opnd(1) # the module
      rhs = ctx.stack_opnd(0)
      asm.mov(C_ARGS[0], rhs);
      asm.mov(C_ARGS[1], lhs);
      asm.call(C.rb_obj_is_kind_of)

      # Return the result
      ctx.stack_pop(2)
      stack_ret = ctx.stack_push(Type::UnknownImm)
      asm.mov(stack_ret, C_RET)

      return true
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_int_equal(jit, ctx, asm, argc, _known_recv_class)
      return false if argc != 1
      return false unless two_fixnums_on_stack?(jit)

      guard_two_fixnums(jit, ctx, asm)

      # Compare the arguments
      asm.comment('rb_int_equal')
      arg1 = ctx.stack_pop(1)
      arg0 = ctx.stack_pop(1)
      asm.mov(:rax, arg1)
      asm.cmp(arg0, :rax)
      asm.mov(:rax, Qfalse)
      asm.mov(:rcx, Qtrue)
      asm.cmove(:rax, :rcx)

      stack_ret = ctx.stack_push(Type::UnknownImm)
      asm.mov(stack_ret, :rax)
      true
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_int_mul(jit, ctx, asm, argc, _known_recv_class)
      return false if argc != 1
      return false unless two_fixnums_on_stack?(jit)

      guard_two_fixnums(jit, ctx, asm)

      asm.comment('rb_int_mul')
      y_opnd = ctx.stack_pop
      x_opnd = ctx.stack_pop
      asm.mov(C_ARGS[0], x_opnd)
      asm.mov(C_ARGS[1], y_opnd)
      asm.call(C.rb_fix_mul_fix)

      ret_opnd = ctx.stack_push(Type::Unknown)
      asm.mov(ret_opnd, C_RET)
      true
    end

    def jit_rb_int_div(jit, ctx, asm, argc, _known_recv_class)
      return false if argc != 1
      return false unless two_fixnums_on_stack?(jit)

      guard_two_fixnums(jit, ctx, asm)

      asm.comment('rb_int_div')
      y_opnd = ctx.stack_pop
      x_opnd = ctx.stack_pop
      asm.mov(:rax, y_opnd)
      asm.cmp(:rax, C.to_value(0))
      asm.je(side_exit(jit, ctx))

      asm.mov(C_ARGS[0], x_opnd)
      asm.mov(C_ARGS[1], :rax)
      asm.call(C.rb_fix_div_fix)

      ret_opnd = ctx.stack_push(Type::Unknown)
      asm.mov(ret_opnd, C_RET)
      true
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_int_aref(jit, ctx, asm, argc, _known_recv_class)
      return false if argc != 1
      return false unless two_fixnums_on_stack?(jit)

      guard_two_fixnums(jit, ctx, asm)

      asm.comment('rb_int_aref')
      y_opnd = ctx.stack_pop
      x_opnd = ctx.stack_pop

      asm.mov(C_ARGS[0], x_opnd)
      asm.mov(C_ARGS[1], y_opnd)
      asm.call(C.rb_fix_aref)

      ret_opnd = ctx.stack_push(Type::UnknownImm)
      asm.mov(ret_opnd, C_RET)
      true
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_str_empty_p(jit, ctx, asm, argc, known_recv_class)
      recv_opnd = ctx.stack_pop(1)
      out_opnd = ctx.stack_push(Type::UnknownImm)

      asm.comment('get string length')
      asm.mov(:rax, recv_opnd)
      str_len_opnd = [:rax, C.RString.offsetof(:len)]

      asm.cmp(str_len_opnd, 0)
      asm.mov(:rax, Qfalse)
      asm.mov(:rcx, Qtrue)
      asm.cmove(:rax, :rcx)
      asm.mov(out_opnd, :rax)

      return true
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_str_to_s(jit, ctx, asm, argc, known_recv_class)
      return false if argc != 0
      if known_recv_class == String
        asm.comment('to_s on plain string')
        # The method returns the receiver, which is already on the stack.
        # No stack movement.
        return true
      end
      false
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_str_bytesize(jit, ctx, asm, argc, known_recv_class)
      asm.comment('String#bytesize')

      recv = ctx.stack_pop(1)
      asm.mov(C_ARGS[0], recv)
      asm.call(C.rb_str_bytesize)

      out_opnd = ctx.stack_push(Type::Fixnum)
      asm.mov(out_opnd, C_RET)

      true
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_str_concat(jit, ctx, asm, argc, known_recv_class)
      # The << operator can accept integer codepoints for characters
      # as the argument. We only specially optimise string arguments.
      # If the peeked-at compile time argument is something other than
      # a string, assume it won't be a string later either.
      comptime_arg = jit.peek_at_stack(0)
      unless C.RB_TYPE_P(comptime_arg, C::RUBY_T_STRING)
        return false
      end

      # Guard that the concat argument is a string
      asm.mov(:rax, ctx.stack_opnd(0))
      guard_object_is_string(jit, ctx, asm, :rax, :rcx, StackOpnd[0])

      # Guard buffers from GC since rb_str_buf_append may allocate. During the VM lock on GC,
      # other Ractors may trigger global invalidation, so we need ctx.clear_local_types.
      # PC is used on errors like Encoding::CompatibilityError raised by rb_str_buf_append.
      jit_prepare_routine_call(jit, ctx, asm)

      concat_arg = ctx.stack_pop(1)
      recv = ctx.stack_pop(1)

      # Test if string encodings differ. If different, use rb_str_append. If the same,
      # use rb_yjit_str_simple_append, which calls rb_str_cat.
      asm.comment('<< on strings')

      # Take receiver's object flags XOR arg's flags. If any
      # string-encoding flags are different between the two,
      # the encodings don't match.
      recv_reg = :rax
      asm.mov(recv_reg, recv)
      concat_arg_reg = :rcx
      asm.mov(concat_arg_reg, concat_arg)
      asm.mov(recv_reg, [recv_reg, C.RBasic.offsetof(:flags)])
      asm.mov(concat_arg_reg, [concat_arg_reg, C.RBasic.offsetof(:flags)])
      asm.xor(recv_reg, concat_arg_reg)
      asm.test(recv_reg, C::RUBY_ENCODING_MASK)

      # Push once, use the resulting operand in both branches below.
      stack_ret = ctx.stack_push(Type::TString)

      enc_mismatch = asm.new_label('enc_mismatch')
      asm.jnz(enc_mismatch)

      # If encodings match, call the simple append function and jump to return
      asm.mov(C_ARGS[0], recv)
      asm.mov(C_ARGS[1], concat_arg)
      asm.call(C.rjit_str_simple_append)
      ret_label = asm.new_label('func_return')
      asm.mov(stack_ret, C_RET)
      asm.jmp(ret_label)

      # If encodings are different, use a slower encoding-aware concatenate
      asm.write_label(enc_mismatch)
      asm.mov(C_ARGS[0], recv)
      asm.mov(C_ARGS[1], concat_arg)
      asm.call(C.rb_str_buf_append)
      asm.mov(stack_ret, C_RET)
      # Drop through to return

      asm.write_label(ret_label)

      true
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_str_uplus(jit, ctx, asm, argc, _known_recv_class)
      if argc != 0
        return false
      end

      # We allocate when we dup the string
      jit_prepare_routine_call(jit, ctx, asm)

      asm.comment('Unary plus on string')
      asm.mov(:rax, ctx.stack_pop(1)) # recv_opnd
      asm.mov(:rcx, [:rax, C.RBasic.offsetof(:flags)]) # flags_opnd
      asm.test(:rcx, C::RUBY_FL_FREEZE)

      ret_label = asm.new_label('stack_ret')

      # String#+@ can only exist on T_STRING
      stack_ret = ctx.stack_push(Type::TString)

      # If the string isn't frozen, we just return it.
      asm.mov(stack_ret, :rax) # recv_opnd
      asm.jz(ret_label)

      # Str is frozen - duplicate it
      asm.mov(C_ARGS[0], :rax) # recv_opnd
      asm.call(C.rb_str_dup)
      asm.mov(stack_ret, C_RET)

      asm.write_label(ret_label)

      true
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_str_getbyte(jit, ctx, asm, argc, _known_recv_class)
      return false if argc != 1
      asm.comment('rb_str_getbyte')

      index_opnd = ctx.stack_pop
      str_opnd = ctx.stack_pop
      asm.mov(C_ARGS[0], str_opnd)
      asm.mov(C_ARGS[1], index_opnd)
      asm.call(C.rb_str_getbyte)

      ret_opnd = ctx.stack_push(Type::Fixnum)
      asm.mov(ret_opnd, C_RET)
      true
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_ary_empty_p(jit, ctx, asm, argc, _known_recv_class)
      array_reg = :rax
      asm.mov(array_reg, ctx.stack_pop(1))
      jit_array_len(asm, array_reg, :rcx)

      asm.test(:rcx, :rcx)
      asm.mov(:rax, Qfalse)
      asm.mov(:rcx, Qtrue)
      asm.cmovz(:rax, :rcx)

      out_opnd = ctx.stack_push(Type::UnknownImm)
      asm.mov(out_opnd, :rax)

      return true
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_ary_push(jit, ctx, asm, argc, _known_recv_class)
      return false if argc != 1
      asm.comment('rb_ary_push')

      jit_prepare_routine_call(jit, ctx, asm)

      item_opnd = ctx.stack_pop
      ary_opnd = ctx.stack_pop
      asm.mov(C_ARGS[0], ary_opnd)
      asm.mov(C_ARGS[1], item_opnd)
      asm.call(C.rb_ary_push)

      ret_opnd = ctx.stack_push(Type::TArray)
      asm.mov(ret_opnd, C_RET)
      true
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_obj_respond_to(jit, ctx, asm, argc, known_recv_class)
      # respond_to(:sym) or respond_to(:sym, true)
      if argc != 1 && argc != 2
        return false
      end

      if known_recv_class.nil?
        return false
      end

      recv_class = known_recv_class

      # Get the method_id from compile time. We will later add a guard against it.
      mid_sym = jit.peek_at_stack(argc - 1)
      unless static_symbol?(mid_sym)
        return false
      end
      mid = C.rb_sym2id(mid_sym)

      # This represents the value of the "include_all" argument and whether it's known
      allow_priv = if argc == 1
        # Default is false
        false
      else
        # Get value from type information (may or may not be known)
        ctx.get_opnd_type(StackOpnd[0]).known_truthy
      end

      target_cme = C.rb_callable_method_entry_or_negative(recv_class, mid)

      # Should never be null, as in that case we will be returned a "negative CME"
      assert_equal(false, target_cme.nil?)

      cme_def_type = C.UNDEFINED_METHOD_ENTRY_P(target_cme) ? C::VM_METHOD_TYPE_UNDEF : target_cme.def.type

      if cme_def_type == C::VM_METHOD_TYPE_REFINED
        return false
      end

      visibility = if cme_def_type == C::VM_METHOD_TYPE_UNDEF
        C::METHOD_VISI_UNDEF
      else
        C.METHOD_ENTRY_VISI(target_cme)
      end

      result =
        case [visibility, allow_priv]
        in C::METHOD_VISI_UNDEF, _ then Qfalse # No method => false
        in C::METHOD_VISI_PUBLIC, _ then Qtrue # Public method => true regardless of include_all
        in _, true then Qtrue # include_all => always true
        else return false # not public and include_all not known, can't compile
        end

      if result != Qtrue
        # Only if respond_to_missing? hasn't been overridden
        # In the future, we might want to jit the call to respond_to_missing?
        unless Invariants.assume_method_basic_definition(jit, recv_class, C.idRespond_to_missing)
          return false
        end
      end

      # Invalidate this block if method lookup changes for the method being queried. This works
      # both for the case where a method does or does not exist, as for the latter we asked for a
      # "negative CME" earlier.
      Invariants.assume_method_lookup_stable(jit, target_cme)

      # Generate a side exit
      side_exit = side_exit(jit, ctx)

      if argc == 2
        # pop include_all argument (we only use its type info)
        ctx.stack_pop(1)
      end

      sym_opnd = ctx.stack_pop(1)
      _recv_opnd = ctx.stack_pop(1)

      # This is necessary because we have no guarantee that sym_opnd is a constant
      asm.comment('guard known mid')
      asm.mov(:rax, to_value(mid_sym))
      asm.cmp(sym_opnd, :rax)
      asm.jne(side_exit)

      putobject(jit, ctx, asm, val: result)

      true
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_rb_f_block_given_p(jit, ctx, asm, argc, _known_recv_class)
      asm.comment('block_given?')

      # Same as rb_vm_frame_block_handler
      jit_get_lep(jit, asm, reg: :rax)
      asm.mov(:rax, [:rax, C.VALUE.size * C::VM_ENV_DATA_INDEX_SPECVAL]) # block_handler

      ctx.stack_pop(1)
      out_opnd = ctx.stack_push(Type::UnknownImm)

      # Return `block_handler != VM_BLOCK_HANDLER_NONE`
      asm.cmp(:rax, C::VM_BLOCK_HANDLER_NONE)
      asm.mov(:rax, Qfalse)
      asm.mov(:rcx, Qtrue)
      asm.cmovne(:rax, :rcx) # block_given
      asm.mov(out_opnd, :rax)

      true
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_thread_s_current(jit, ctx, asm, argc, _known_recv_class)
      return false if argc != 0
      asm.comment('Thread.current')
      ctx.stack_pop(1)

      # ec->thread_ptr
      asm.mov(:rax, [EC, C.rb_execution_context_t.offsetof(:thread_ptr)])

      # thread->self
      asm.mov(:rax, [:rax, C.rb_thread_struct.offsetof(:self)])

      stack_ret = ctx.stack_push(Type::UnknownHeap)
      asm.mov(stack_ret, :rax)
      true
    end

    #
    # Helpers
    #

    def register_cfunc_codegen_funcs
      # Specialization for C methods. See register_cfunc_method for details.
      register_cfunc_method(BasicObject, :!, :jit_rb_obj_not)

      register_cfunc_method(NilClass, :nil?, :jit_rb_true)
      register_cfunc_method(Kernel, :nil?, :jit_rb_false)
      register_cfunc_method(Kernel, :is_a?, :jit_rb_kernel_is_a)
      register_cfunc_method(Kernel, :kind_of?, :jit_rb_kernel_is_a)
      register_cfunc_method(Kernel, :instance_of?, :jit_rb_kernel_instance_of)

      register_cfunc_method(BasicObject, :==, :jit_rb_obj_equal)
      register_cfunc_method(BasicObject, :equal?, :jit_rb_obj_equal)
      register_cfunc_method(BasicObject, :!=, :jit_rb_obj_not_equal)
      register_cfunc_method(Kernel, :eql?, :jit_rb_obj_equal)
      register_cfunc_method(Module, :==, :jit_rb_obj_equal)
      register_cfunc_method(Module, :===, :jit_rb_mod_eqq)
      register_cfunc_method(Symbol, :==, :jit_rb_obj_equal)
      register_cfunc_method(Symbol, :===, :jit_rb_obj_equal)
      register_cfunc_method(Integer, :==, :jit_rb_int_equal)
      register_cfunc_method(Integer, :===, :jit_rb_int_equal)

      # rb_str_to_s() methods in string.c
      register_cfunc_method(String, :empty?, :jit_rb_str_empty_p)
      register_cfunc_method(String, :to_s, :jit_rb_str_to_s)
      register_cfunc_method(String, :to_str, :jit_rb_str_to_s)
      register_cfunc_method(String, :bytesize, :jit_rb_str_bytesize)
      register_cfunc_method(String, :<<, :jit_rb_str_concat)
      register_cfunc_method(String, :+@, :jit_rb_str_uplus)

      # rb_ary_empty_p() method in array.c
      register_cfunc_method(Array, :empty?, :jit_rb_ary_empty_p)

      register_cfunc_method(Kernel, :respond_to?, :jit_obj_respond_to)
      register_cfunc_method(Kernel, :block_given?, :jit_rb_f_block_given_p)

      # Thread.current
      register_cfunc_method(C.rb_singleton_class(Thread), :current, :jit_thread_s_current)

      #---
      register_cfunc_method(Array, :<<, :jit_rb_ary_push)
      register_cfunc_method(Integer, :*, :jit_rb_int_mul)
      register_cfunc_method(Integer, :/, :jit_rb_int_div)
      register_cfunc_method(Integer, :[], :jit_rb_int_aref)
      register_cfunc_method(String, :getbyte, :jit_rb_str_getbyte)
    end

    def register_cfunc_method(klass, mid_sym, func)
      mid = C.rb_intern(mid_sym.to_s)
      me = C.rb_method_entry_at(klass, mid)

      assert_equal(false, me.nil?)

      # Only cfuncs are supported
      method_serial = me.def.method_serial

      @cfunc_codegen_table[method_serial] = method(func)
    end

    def lookup_cfunc_codegen(cme_def)
      @cfunc_codegen_table[cme_def.method_serial]
    end

    def stack_swap(_jit, ctx, asm, offset0, offset1)
      stack0_mem = ctx.stack_opnd(offset0)
      stack1_mem = ctx.stack_opnd(offset1)

      mapping0 = ctx.get_opnd_mapping(StackOpnd[offset0])
      mapping1 = ctx.get_opnd_mapping(StackOpnd[offset1])

      asm.mov(:rax, stack0_mem)
      asm.mov(:rcx, stack1_mem)
      asm.mov(stack0_mem, :rcx)
      asm.mov(stack1_mem, :rax)

      ctx.set_opnd_mapping(StackOpnd[offset0], mapping1)
      ctx.set_opnd_mapping(StackOpnd[offset1], mapping0)
    end

    def jit_getlocal_generic(jit, ctx, asm, idx:, level:)
      # Load environment pointer EP (level 0) from CFP
      ep_reg = :rax
      jit_get_ep(asm, level, reg: ep_reg)

      # Load the local from the block
      # val = *(vm_get_ep(GET_EP(), level) - idx);
      asm.mov(:rax, [ep_reg, -idx * C.VALUE.size])

      # Write the local at SP
      stack_top = if level == 0
        local_idx = ep_offset_to_local_idx(jit.iseq, idx)
        ctx.stack_push_local(local_idx)
      else
        ctx.stack_push(Type::Unknown)
      end

      asm.mov(stack_top, :rax)
      KeepCompiling
    end

    def jit_setlocal_generic(jit, ctx, asm, idx:, level:)
      value_type = ctx.get_opnd_type(StackOpnd[0])

      # Load environment pointer EP at level
      ep_reg = :rax
      jit_get_ep(asm, level, reg: ep_reg)

      # Write barriers may be required when VM_ENV_FLAG_WB_REQUIRED is set, however write barriers
      # only affect heap objects being written. If we know an immediate value is being written we
      # can skip this check.
      unless value_type.imm?
        # flags & VM_ENV_FLAG_WB_REQUIRED
        flags_opnd = [ep_reg, C.VALUE.size * C::VM_ENV_DATA_INDEX_FLAGS]
        asm.test(flags_opnd, C::VM_ENV_FLAG_WB_REQUIRED)

        # if (flags & VM_ENV_FLAG_WB_REQUIRED) != 0
        asm.jnz(side_exit(jit, ctx))
      end

      if level == 0
        local_idx = ep_offset_to_local_idx(jit.iseq, idx)
        ctx.set_local_type(local_idx, value_type)
      end

      # Pop the value to write from the stack
      stack_top = ctx.stack_pop(1)

      # Write the value at the environment pointer
      asm.mov(:rcx, stack_top)
      asm.mov([ep_reg, -(C.VALUE.size * idx)], :rcx)

      KeepCompiling
    end

    # Compute the index of a local variable from its slot index
    def ep_offset_to_local_idx(iseq, ep_offset)
      # Layout illustration
      # This is an array of VALUE
      #                                           | VM_ENV_DATA_SIZE |
      #                                           v                  v
      # low addr <+-------+-------+-------+-------+------------------+
      #           |local 0|local 1|  ...  |local n|       ....       |
      #           +-------+-------+-------+-------+------------------+
      #           ^       ^                       ^                  ^
      #           +-------+---local_table_size----+         cfp->ep--+
      #                   |                                          |
      #                   +------------------ep_offset---------------+
      #
      # See usages of local_var_name() from iseq.c for similar calculation.

      # Equivalent of iseq->body->local_table_size
      local_table_size = iseq.body.local_table_size
      op = ep_offset - C::VM_ENV_DATA_SIZE
      local_idx = local_table_size - op - 1
      assert_equal(true, local_idx >= 0 && local_idx < local_table_size)
      local_idx
    end

    # Compute the index of a local variable from its slot index
    def slot_to_local_idx(iseq, slot_idx)
      # Layout illustration
      # This is an array of VALUE
      #                                           | VM_ENV_DATA_SIZE |
      #                                           v                  v
      # low addr <+-------+-------+-------+-------+------------------+
      #           |local 0|local 1|  ...  |local n|       ....       |
      #           +-------+-------+-------+-------+------------------+
      #           ^       ^                       ^                  ^
      #           +-------+---local_table_size----+         cfp->ep--+
      #                   |                                          |
      #                   +------------------slot_idx----------------+
      #
      # See usages of local_var_name() from iseq.c for similar calculation.

      local_table_size = iseq.body.local_table_size
      op = slot_idx - C::VM_ENV_DATA_SIZE
      local_table_size - op - 1
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def guard_object_is_heap(jit, ctx, asm, object, object_opnd, counter = nil)
      object_type = ctx.get_opnd_type(object_opnd)
      if object_type.heap?
        return
      end

      side_exit = side_exit(jit, ctx)
      side_exit = counted_exit(side_exit, counter) if counter

      asm.comment('guard object is heap')
      # Test that the object is not an immediate
      asm.test(object, C::RUBY_IMMEDIATE_MASK)
      asm.jnz(side_exit)

      # Test that the object is not false
      asm.cmp(object, Qfalse)
      asm.je(side_exit)

      if object_type.diff(Type::UnknownHeap) != TypeDiff::Incompatible
        ctx.upgrade_opnd_type(object_opnd, Type::UnknownHeap)
      end
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def guard_object_is_array(jit, ctx, asm, object_reg, flags_reg, object_opnd, counter = nil)
      object_type = ctx.get_opnd_type(object_opnd)
      if object_type.array?
        return
      end

      guard_object_is_heap(jit, ctx, asm, object_reg, object_opnd, counter)

      side_exit = side_exit(jit, ctx)
      side_exit = counted_exit(side_exit, counter) if counter

      asm.comment('guard object is array')
      # Pull out the type mask
      asm.mov(flags_reg, [object_reg, C.RBasic.offsetof(:flags)])
      asm.and(flags_reg, C::RUBY_T_MASK)

      # Compare the result with T_ARRAY
      asm.cmp(flags_reg, C::RUBY_T_ARRAY)
      asm.jne(side_exit)

      if object_type.diff(Type::TArray) != TypeDiff::Incompatible
        ctx.upgrade_opnd_type(object_opnd, Type::TArray)
      end
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def guard_object_is_string(jit, ctx, asm, object_reg, flags_reg, object_opnd, counter = nil)
      object_type = ctx.get_opnd_type(object_opnd)
      if object_type.string?
        return
      end

      guard_object_is_heap(jit, ctx, asm, object_reg, object_opnd, counter)

      side_exit = side_exit(jit, ctx)
      side_exit = counted_exit(side_exit, counter) if counter

      asm.comment('guard object is string')
      # Pull out the type mask
      asm.mov(flags_reg, [object_reg, C.RBasic.offsetof(:flags)])
      asm.and(flags_reg, C::RUBY_T_MASK)

      # Compare the result with T_STRING
      asm.cmp(flags_reg, C::RUBY_T_STRING)
      asm.jne(side_exit)

      if object_type.diff(Type::TString) != TypeDiff::Incompatible
        ctx.upgrade_opnd_type(object_opnd, Type::TString)
      end
    end

    # clobbers object_reg
    def guard_object_is_not_ruby2_keyword_hash(asm, object_reg, flags_reg, side_exit)
      asm.comment('guard object is not ruby2 keyword hash')

      not_ruby2_keyword = asm.new_label('not_ruby2_keyword')
      asm.test(object_reg, C::RUBY_IMMEDIATE_MASK)
      asm.jnz(not_ruby2_keyword)

      asm.cmp(object_reg, Qfalse)
      asm.je(not_ruby2_keyword)

      asm.mov(flags_reg, [object_reg, C.RBasic.offsetof(:flags)])
      type_reg = object_reg
      asm.mov(type_reg, flags_reg)
      asm.and(type_reg, C::RUBY_T_MASK)

      asm.cmp(type_reg, C::RUBY_T_HASH)
      asm.jne(not_ruby2_keyword)

      asm.test(flags_reg, C::RHASH_PASS_AS_KEYWORDS)
      asm.jnz(side_exit)

      asm.write_label(not_ruby2_keyword)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_chain_guard(opcode, jit, ctx, asm, side_exit, limit: 20)
      opcode => :je | :jne | :jnz | :jz

      if ctx.chain_depth < limit
        deeper = ctx.dup
        deeper.chain_depth += 1

        branch_stub = BranchStub.new(
          iseq: jit.iseq,
          shape: Default,
          target0: BranchTarget.new(ctx: deeper, pc: jit.pc),
        )
        branch_stub.target0.address = Assembler.new.then do |ocb_asm|
          @exit_compiler.compile_branch_stub(deeper, ocb_asm, branch_stub, true)
          @ocb.write(ocb_asm)
        end
        branch_stub.compile = compile_jit_chain_guard(branch_stub, opcode:)
        branch_stub.compile.call(asm)
      else
        asm.public_send(opcode, side_exit)
      end
    end

    def compile_jit_chain_guard(branch_stub, opcode:) # Proc escapes arguments in memory
      proc do |branch_asm|
        # Not using `asm.comment` here since it's usually put before cmp/test before this.
        branch_asm.stub(branch_stub) do
          case branch_stub.shape
          in Default
            branch_asm.public_send(opcode, branch_stub.target0.address)
          end
        end
      end
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_guard_known_klass(jit, ctx, asm, known_klass, obj_opnd, insn_opnd, comptime_obj, side_exit, limit: 10)
      # Only memory operand is supported for now
      assert_equal(true, obj_opnd.is_a?(Array))

      known_klass = C.to_value(known_klass)
      val_type = ctx.get_opnd_type(insn_opnd)
      if val_type.known_class == known_klass
        # We already know from type information that this is a match
        return
      end

      # Touching this as Ruby could crash for FrozenCore
      if known_klass == C.rb_cNilClass
        assert(!val_type.heap?)
        assert(val_type.unknown?)

        asm.comment('guard object is nil')
        asm.cmp(obj_opnd, Qnil)
        jit_chain_guard(:jne, jit, ctx, asm, side_exit, limit:)

        ctx.upgrade_opnd_type(insn_opnd, Type::Nil)
      elsif known_klass == C.rb_cTrueClass
        assert(!val_type.heap?)
        assert(val_type.unknown?)

        asm.comment('guard object is true')
        asm.cmp(obj_opnd, Qtrue)
        jit_chain_guard(:jne, jit, ctx, asm, side_exit, limit:)

        ctx.upgrade_opnd_type(insn_opnd, Type::True)
      elsif known_klass == C.rb_cFalseClass
        assert(!val_type.heap?)
        assert(val_type.unknown?)

        asm.comment('guard object is false')
        asm.cmp(obj_opnd, Qfalse)
        jit_chain_guard(:jne, jit, ctx, asm, side_exit, limit:)

        ctx.upgrade_opnd_type(insn_opnd, Type::False)
      elsif known_klass == C.rb_cInteger && fixnum?(comptime_obj)
        # We will guard fixnum and bignum as though they were separate classes
        # BIGNUM can be handled by the general else case below
        assert(val_type.unknown?)

        asm.comment('guard object is fixnum')
        asm.test(obj_opnd, C::RUBY_FIXNUM_FLAG)
        jit_chain_guard(:jz, jit, ctx, asm, side_exit, limit:)

        ctx.upgrade_opnd_type(insn_opnd, Type::Fixnum)
      elsif known_klass == C.rb_cSymbol && static_symbol?(comptime_obj)
        assert(!val_type.heap?)
        # We will guard STATIC vs DYNAMIC as though they were separate classes
        # DYNAMIC symbols can be handled by the general else case below
        if val_type != Type::ImmSymbol || !val_type.imm?
          assert(val_type.unknown?)

          asm.comment('guard object is static symbol')
          assert_equal(8, C::RUBY_SPECIAL_SHIFT)
          asm.cmp(BytePtr[*obj_opnd], C::RUBY_SYMBOL_FLAG)
          jit_chain_guard(:jne, jit, ctx, asm, side_exit, limit:)

          ctx.upgrade_opnd_type(insn_opnd, Type::ImmSymbol)
        end
      elsif known_klass == C.rb_cFloat && flonum?(comptime_obj)
        assert(!val_type.heap?)
        if val_type != Type::Flonum || !val_type.imm?
          assert(val_type.unknown?)

          # We will guard flonum vs heap float as though they were separate classes
          asm.comment('guard object is flonum')
          asm.mov(:rax, obj_opnd)
          asm.and(:rax, C::RUBY_FLONUM_MASK)
          asm.cmp(:rax, C::RUBY_FLONUM_FLAG)
          jit_chain_guard(:jne, jit, ctx, asm, side_exit, limit:)

          ctx.upgrade_opnd_type(insn_opnd, Type::Flonum)
        end
      elsif C.FL_TEST(known_klass, C::RUBY_FL_SINGLETON) && comptime_obj == C.rb_class_attached_object(known_klass)
        # Singleton classes are attached to one specific object, so we can
        # avoid one memory access (and potentially the is_heap check) by
        # looking for the expected object directly.
        # Note that in case the sample instance has a singleton class that
        # doesn't attach to the sample instance, it means the sample instance
        # has an empty singleton class that hasn't been materialized yet. In
        # this case, comparing against the sample instance doesn't guarantee
        # that its singleton class is empty, so we can't avoid the memory
        # access. As an example, `Object.new.singleton_class` is an object in
        # this situation.
        asm.comment('guard known object with singleton class')
        asm.mov(:rax, to_value(comptime_obj))
        asm.cmp(obj_opnd, :rax)
        jit_chain_guard(:jne, jit, ctx, asm, side_exit, limit:)
      elsif val_type == Type::CString && known_klass == C.rb_cString
        # guard elided because the context says we've already checked
        assert_equal(C.to_value(C.rb_class_of(comptime_obj)), C.rb_cString)
      else
        assert(!val_type.imm?)

        # Load memory to a register
        asm.mov(:rax, obj_opnd)
        obj_opnd = :rax

        # Check that the receiver is a heap object
        # Note: if we get here, the class doesn't have immediate instances.
        unless val_type.heap?
          asm.comment('guard not immediate')
          asm.test(obj_opnd, C::RUBY_IMMEDIATE_MASK)
          jit_chain_guard(:jnz, jit, ctx, asm, side_exit, limit:)
          asm.cmp(obj_opnd, Qfalse)
          jit_chain_guard(:je, jit, ctx, asm, side_exit, limit:)
        end

        # Bail if receiver class is different from known_klass
        klass_opnd = [obj_opnd, C.RBasic.offsetof(:klass)]
        asm.comment("guard known class #{known_klass}")
        asm.mov(:rcx, known_klass)
        asm.cmp(klass_opnd, :rcx)
        jit_chain_guard(:jne, jit, ctx, asm, side_exit, limit:)

        if known_klass == C.rb_cString
          # Upgrading to Type::CString here is incorrect.
          # The guard we put only checks RBASIC_CLASS(obj),
          # which adding a singleton class can change. We
          # additionally need to know the string is frozen
          # to claim Type::CString.
          ctx.upgrade_opnd_type(insn_opnd, Type::TString)
        elsif known_klass == C.rb_cArray
          ctx.upgrade_opnd_type(insn_opnd, Type::TArray)
        end
      end
    end

    # @param jit [RubyVM::RJIT::JITState]
    def two_fixnums_on_stack?(jit)
      comptime_recv = jit.peek_at_stack(1)
      comptime_arg = jit.peek_at_stack(0)
      return fixnum?(comptime_recv) && fixnum?(comptime_arg)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def guard_two_fixnums(jit, ctx, asm)
      # Get stack operands without popping them
      arg1 = ctx.stack_opnd(0)
      arg0 = ctx.stack_opnd(1)

      # Get the stack operand types
      arg1_type = ctx.get_opnd_type(StackOpnd[0])
      arg0_type = ctx.get_opnd_type(StackOpnd[1])

      if arg0_type.heap? || arg1_type.heap?
        asm.comment('arg is heap object')
        asm.jmp(side_exit(jit, ctx))
        return
      end

      if arg0_type != Type::Fixnum && arg0_type.specific?
        asm.comment('arg0 not fixnum')
        asm.jmp(side_exit(jit, ctx))
        return
      end

      if arg1_type != Type::Fixnum && arg1_type.specific?
        asm.comment('arg1 not fixnum')
        asm.jmp(side_exit(jit, ctx))
        return
      end

      assert(!arg0_type.heap?)
      assert(!arg1_type.heap?)
      assert(arg0_type == Type::Fixnum || arg0_type.unknown?)
      assert(arg1_type == Type::Fixnum || arg1_type.unknown?)

      # If not fixnums at run-time, fall back
      if arg0_type != Type::Fixnum
        asm.comment('guard arg0 fixnum')
        asm.test(arg0, C::RUBY_FIXNUM_FLAG)
        jit_chain_guard(:jz, jit, ctx, asm, side_exit(jit, ctx))
      end
      if arg1_type != Type::Fixnum
        asm.comment('guard arg1 fixnum')
        asm.test(arg1, C::RUBY_FIXNUM_FLAG)
        jit_chain_guard(:jz, jit, ctx, asm, side_exit(jit, ctx))
      end

      # Set stack types in context
      ctx.upgrade_opnd_type(StackOpnd[0], Type::Fixnum)
      ctx.upgrade_opnd_type(StackOpnd[1], Type::Fixnum)
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_fixnum_cmp(jit, ctx, asm, opcode:, bop:)
      opcode => :cmovl | :cmovle | :cmovg | :cmovge

      unless jit.at_current_insn?
        defer_compilation(jit, ctx, asm)
        return EndBlock
      end

      comptime_recv = jit.peek_at_stack(1)
      comptime_obj  = jit.peek_at_stack(0)

      if fixnum?(comptime_recv) && fixnum?(comptime_obj)
        unless Invariants.assume_bop_not_redefined(jit, C::INTEGER_REDEFINED_OP_FLAG, bop)
          return CantCompile
        end

        # Check that both operands are fixnums
        guard_two_fixnums(jit, ctx, asm)

        obj_opnd  = ctx.stack_pop
        recv_opnd = ctx.stack_pop

        asm.mov(:rax, obj_opnd)
        asm.cmp(recv_opnd, :rax)
        asm.mov(:rax, Qfalse)
        asm.mov(:rcx, Qtrue)
        asm.public_send(opcode, :rax, :rcx)

        dst_opnd = ctx.stack_push(Type::UnknownImm)
        asm.mov(dst_opnd, :rax)

        KeepCompiling
      else
        opt_send_without_block(jit, ctx, asm)
      end
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_equality_specialized(jit, ctx, asm, gen_eq)
      # Create a side-exit to fall back to the interpreter
      side_exit = side_exit(jit, ctx)

      a_opnd = ctx.stack_opnd(1)
      b_opnd = ctx.stack_opnd(0)

      comptime_a = jit.peek_at_stack(1)
      comptime_b = jit.peek_at_stack(0)

      if two_fixnums_on_stack?(jit)
        unless Invariants.assume_bop_not_redefined(jit, C::INTEGER_REDEFINED_OP_FLAG, C::BOP_EQ)
          return false
        end

        guard_two_fixnums(jit, ctx, asm)

        asm.comment('check fixnum equality')
        asm.mov(:rax, a_opnd)
        asm.mov(:rcx, b_opnd)
        asm.cmp(:rax, :rcx)
        asm.mov(:rax, gen_eq ? Qfalse : Qtrue)
        asm.mov(:rcx, gen_eq ? Qtrue  : Qfalse)
        asm.cmove(:rax, :rcx)

        # Push the output on the stack
        ctx.stack_pop(2)
        dst = ctx.stack_push(Type::UnknownImm)
        asm.mov(dst, :rax)

        true
      elsif C.rb_class_of(comptime_a) == String && C.rb_class_of(comptime_b) == String
        unless Invariants.assume_bop_not_redefined(jit, C::STRING_REDEFINED_OP_FLAG, C::BOP_EQ)
          # if overridden, emit the generic version
          return false
        end

        # Guard that a is a String
        jit_guard_known_klass(jit, ctx, asm, C.rb_class_of(comptime_a), a_opnd, StackOpnd[1], comptime_a, side_exit)

        equal_label = asm.new_label(:equal)
        ret_label = asm.new_label(:ret)

        # If they are equal by identity, return true
        asm.mov(:rax, a_opnd)
        asm.mov(:rcx, b_opnd)
        asm.cmp(:rax, :rcx)
        asm.je(equal_label)

        # Otherwise guard that b is a T_STRING (from type info) or String (from runtime guard)
        btype = ctx.get_opnd_type(StackOpnd[0])
        unless btype.string?
          # Note: any T_STRING is valid here, but we check for a ::String for simplicity
          # To pass a mutable static variable (rb_cString) requires an unsafe block
          jit_guard_known_klass(jit, ctx, asm, C.rb_class_of(comptime_b), b_opnd, StackOpnd[0], comptime_b, side_exit)
        end

        asm.comment('call rb_str_eql_internal')
        asm.mov(C_ARGS[0], a_opnd)
        asm.mov(C_ARGS[1], b_opnd)
        asm.call(gen_eq ? C.rb_str_eql_internal : C.rjit_str_neq_internal)

        # Push the output on the stack
        ctx.stack_pop(2)
        dst = ctx.stack_push(Type::UnknownImm)
        asm.mov(dst, C_RET)
        asm.jmp(ret_label)

        asm.write_label(equal_label)
        asm.mov(dst, gen_eq ? Qtrue : Qfalse)

        asm.write_label(ret_label)

        true
      else
        false
      end
    end

    # NOTE: This clobbers :rax
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_prepare_routine_call(jit, ctx, asm)
      jit.record_boundary_patch_point = true
      jit_save_pc(jit, asm)
      jit_save_sp(ctx, asm)

      # In case the routine calls Ruby methods, it can set local variables
      # through Kernel#binding and other means.
      ctx.clear_local_types
    end

    # NOTE: This clobbers :rax
    # @param jit [RubyVM::RJIT::JITState]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_save_pc(jit, asm, comment: 'save PC to CFP')
      next_pc = jit.pc + jit.insn.len * C.VALUE.size # Use the next one for backtrace and side exits
      asm.comment(comment)
      asm.mov(:rax, next_pc)
      asm.mov([CFP, C.rb_control_frame_t.offsetof(:pc)], :rax)
    end

    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_save_sp(ctx, asm)
      if ctx.sp_offset != 0
        asm.comment('save SP to CFP')
        asm.lea(SP, ctx.sp_opnd)
        asm.mov([CFP, C.rb_control_frame_t.offsetof(:sp)], SP)
        ctx.sp_offset = 0
      end
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jump_to_next_insn(jit, ctx, asm)
      reset_depth = ctx.dup
      reset_depth.chain_depth = 0

      next_pc = jit.pc + jit.insn.len * C.VALUE.size

      # We are at the end of the current instruction. Record the boundary.
      if jit.record_boundary_patch_point
        exit_pos = Assembler.new.then do |ocb_asm|
          @exit_compiler.compile_side_exit(next_pc, ctx, ocb_asm)
          @ocb.write(ocb_asm)
        end
        Invariants.record_global_inval_patch(asm, exit_pos)
        jit.record_boundary_patch_point = false
      end

      jit_direct_jump(jit.iseq, next_pc, reset_depth, asm, comment: 'jump_to_next_insn')
    end

    # rb_vm_check_ints
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_check_ints(jit, ctx, asm)
      asm.comment('RUBY_VM_CHECK_INTS(ec)')
      asm.mov(:eax, DwordPtr[EC, C.rb_execution_context_t.offsetof(:interrupt_flag)])
      asm.test(:eax, :eax)
      asm.jnz(side_exit(jit, ctx))
    end

    # See get_lvar_level in compile.c
    def get_lvar_level(iseq)
      level = 0
      while iseq.to_i != iseq.body.local_iseq.to_i
        level += 1
        iseq = iseq.body.parent_iseq
      end
      return level
    end

    # GET_LEP
    # @param jit [RubyVM::RJIT::JITState]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_get_lep(jit, asm, reg:)
      level = get_lvar_level(jit.iseq)
      jit_get_ep(asm, level, reg:)
    end

    # vm_get_ep
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_get_ep(asm, level, reg:)
      asm.mov(reg, [CFP, C.rb_control_frame_t.offsetof(:ep)])
      level.times do
        # GET_PREV_EP: ep[VM_ENV_DATA_INDEX_SPECVAL] & ~0x03
        asm.mov(reg, [reg, C.VALUE.size * C::VM_ENV_DATA_INDEX_SPECVAL])
        asm.and(reg, ~0x03)
      end
    end

    # vm_getivar
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_getivar(jit, ctx, asm, comptime_obj, ivar_id, obj_opnd, obj_yarv_opnd)
      side_exit = side_exit(jit, ctx)
      starting_ctx = ctx.dup # copy for jit_chain_guard

      # Guard not special const
      if C::SPECIAL_CONST_P(comptime_obj)
        asm.incr_counter(:getivar_special_const)
        return CantCompile
      end

      case C::BUILTIN_TYPE(comptime_obj)
      when C::T_OBJECT
        # This is the only supported case for now (ROBJECT_IVPTR)
      else
        # General case. Call rb_ivar_get().
        # VALUE rb_ivar_get(VALUE obj, ID id)
        asm.comment('call rb_ivar_get()')
        asm.mov(C_ARGS[0], obj_opnd ? obj_opnd : [CFP, C.rb_control_frame_t.offsetof(:self)])
        asm.mov(C_ARGS[1], ivar_id)

        # The function could raise exceptions.
        jit_prepare_routine_call(jit, ctx, asm) # clobbers obj_opnd and :rax

        asm.call(C.rb_ivar_get)

        if obj_opnd # attr_reader
          ctx.stack_pop
        end

        # Push the ivar on the stack
        out_opnd = ctx.stack_push(Type::Unknown)
        asm.mov(out_opnd, C_RET)

        # Jump to next instruction. This allows guard chains to share the same successor.
        jump_to_next_insn(jit, ctx, asm)
        return EndBlock
      end

      asm.mov(:rax, obj_opnd ? obj_opnd : [CFP, C.rb_control_frame_t.offsetof(:self)])
      guard_object_is_heap(jit, ctx, asm, :rax, obj_yarv_opnd, :getivar_not_heap)

      shape_id = C.rb_shape_get_shape_id(comptime_obj)
      if shape_id == C::OBJ_TOO_COMPLEX_SHAPE_ID
        asm.incr_counter(:getivar_too_complex)
        return CantCompile
      end

      asm.comment('guard shape')
      asm.cmp(DwordPtr[:rax, C.rb_shape_id_offset], shape_id)
      jit_chain_guard(:jne, jit, starting_ctx, asm, counted_exit(side_exit, :getivar_megamorphic))

      if obj_opnd
        ctx.stack_pop # pop receiver for attr_reader
      end

      index = C.rb_shape_get_iv_index(shape_id, ivar_id)
      # If there is no IVAR index, then the ivar was undefined
      # when we entered the compiler.  That means we can just return
      # nil for this shape + iv name
      if index.nil?
        stack_opnd = ctx.stack_push(Type::Nil)
        val_opnd = Qnil
      else
        asm.comment('ROBJECT_IVPTR')
        if C::FL_TEST_RAW(comptime_obj, C::ROBJECT_EMBED)
          # Access embedded array
          asm.mov(:rax, [:rax, C.RObject.offsetof(:as, :ary) + (index * C.VALUE.size)])
        else
          # Pull out an ivar table on heap
          asm.mov(:rax, [:rax, C.RObject.offsetof(:as, :heap, :ivptr)])
          # Read the table
          asm.mov(:rax, [:rax, index * C.VALUE.size])
        end
        stack_opnd = ctx.stack_push(Type::Unknown)
        val_opnd = :rax
      end
      asm.mov(stack_opnd, val_opnd)

      # Let guard chains share the same successor
      jump_to_next_insn(jit, ctx, asm)
      EndBlock
    end

    def jit_write_iv(asm, comptime_receiver, recv_reg, temp_reg, ivar_index, set_value, needs_extension)
      # Compile time self is embedded and the ivar index lands within the object
      embed_test_result = C::FL_TEST_RAW(comptime_receiver, C::ROBJECT_EMBED) && !needs_extension

      if embed_test_result
        # Find the IV offset
        offs = C.RObject.offsetof(:as, :ary) + ivar_index * C.VALUE.size

        # Write the IV
        asm.comment('write IV')
        asm.mov(temp_reg, set_value)
        asm.mov([recv_reg, offs], temp_reg)
      else
        # Compile time value is *not* embedded.

        # Get a pointer to the extended table
        asm.mov(recv_reg, [recv_reg, C.RObject.offsetof(:as, :heap, :ivptr)])

        # Write the ivar in to the extended table
        asm.comment("write IV");
        asm.mov(temp_reg, set_value)
        asm.mov([recv_reg, C.VALUE.size * ivar_index], temp_reg)
      end
    end

    # vm_caller_setup_arg_block: Handle VM_CALL_ARGS_BLOCKARG cases.
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def guard_block_arg(jit, ctx, asm, calling)
      if calling.flags & C::VM_CALL_ARGS_BLOCKARG != 0
        block_arg_type = ctx.get_opnd_type(StackOpnd[0])
        case block_arg_type
        in Type::Nil
          calling.block_handler = C::VM_BLOCK_HANDLER_NONE
        in Type::BlockParamProxy
          calling.block_handler = C.rb_block_param_proxy
        else
          asm.incr_counter(:send_block_arg)
          return CantCompile
        end
      end
    end

    # vm_search_method
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_search_method(jit, ctx, asm, mid, calling)
      assert_equal(true, jit.at_current_insn?)

      # Generate a side exit
      side_exit = side_exit(jit, ctx)

      # kw_splat is not supported yet
      if calling.flags & C::VM_CALL_KW_SPLAT != 0
        asm.incr_counter(:send_kw_splat)
        return CantCompile
      end

      # Get a compile-time receiver and its class
      recv_idx = calling.argc + (calling.flags & C::VM_CALL_ARGS_BLOCKARG != 0 ? 1 : 0) # blockarg is not popped yet
      recv_idx += calling.send_shift
      comptime_recv = jit.peek_at_stack(recv_idx)
      comptime_recv_klass = C.rb_class_of(comptime_recv)

      # Guard the receiver class (part of vm_search_method_fastpath)
      recv_opnd = ctx.stack_opnd(recv_idx)
      megamorphic_exit = counted_exit(side_exit, :send_klass_megamorphic)
      jit_guard_known_klass(jit, ctx, asm, comptime_recv_klass, recv_opnd, StackOpnd[recv_idx], comptime_recv, megamorphic_exit)

      # Do method lookup (vm_cc_cme(cc) != NULL)
      cme = C.rb_callable_method_entry(comptime_recv_klass, mid)
      if cme.nil?
        asm.incr_counter(:send_missing_cme)
        return CantCompile # We don't support vm_call_method_name
      end

      # Invalidate on redefinition (part of vm_search_method_fastpath)
      Invariants.assume_method_lookup_stable(jit, cme)

      return cme, comptime_recv_klass
    end

    # vm_call_general
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_call_general(jit, ctx, asm, mid, calling, cme, known_recv_class)
      jit_call_method(jit, ctx, asm, mid, calling, cme, known_recv_class)
    end

    # vm_call_method
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    # @param send_shift [Integer] The number of shifts needed for VM_CALL_OPT_SEND
    def jit_call_method(jit, ctx, asm, mid, calling, cme, known_recv_class)
      # The main check of vm_call_method before vm_call_method_each_type
      case C::METHOD_ENTRY_VISI(cme)
      in C::METHOD_VISI_PUBLIC
        # You can always call public methods
      in C::METHOD_VISI_PRIVATE
        # Allow only callsites without a receiver
        if calling.flags & C::VM_CALL_FCALL == 0
          asm.incr_counter(:send_private)
          return CantCompile
        end
      in C::METHOD_VISI_PROTECTED
        # If the method call is an FCALL, it is always valid
        if calling.flags & C::VM_CALL_FCALL == 0
          # otherwise we need an ancestry check to ensure the receiver is valid to be called as protected
          jit_protected_callee_ancestry_guard(asm, cme, side_exit(jit, ctx))
        end
      end

      # Get a compile-time receiver
      recv_idx = calling.argc + (calling.flags & C::VM_CALL_ARGS_BLOCKARG != 0 ? 1 : 0) # blockarg is not popped yet
      recv_idx += calling.send_shift
      comptime_recv = jit.peek_at_stack(recv_idx)
      recv_opnd = ctx.stack_opnd(recv_idx)

      jit_call_method_each_type(jit, ctx, asm, calling, cme, comptime_recv, recv_opnd, known_recv_class)
    end

    # Generate ancestry guard for protected callee.
    # Calls to protected callees only go through when self.is_a?(klass_that_defines_the_callee).
    def jit_protected_callee_ancestry_guard(asm, cme, side_exit)
      # See vm_call_method().
      def_class = cme.defined_class
      # Note: PC isn't written to current control frame as rb_is_kind_of() shouldn't raise.
      # VALUE rb_obj_is_kind_of(VALUE obj, VALUE klass);

      asm.mov(C_ARGS[0], [CFP, C.rb_control_frame_t.offsetof(:self)])
      asm.mov(C_ARGS[1], to_value(def_class))
      asm.call(C.rb_obj_is_kind_of)
      asm.test(C_RET, C_RET)
      asm.jz(counted_exit(side_exit, :send_protected_check_failed))
    end

    # vm_call_method_each_type
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_call_method_each_type(jit, ctx, asm, calling, cme, comptime_recv, recv_opnd, known_recv_class)
      case cme.def.type
      in C::VM_METHOD_TYPE_ISEQ
        iseq = def_iseq_ptr(cme.def)
        jit_call_iseq(jit, ctx, asm, cme, calling, iseq)
      in C::VM_METHOD_TYPE_NOTIMPLEMENTED
        asm.incr_counter(:send_notimplemented)
        return CantCompile
      in C::VM_METHOD_TYPE_CFUNC
        jit_call_cfunc(jit, ctx, asm, cme, calling, known_recv_class:)
      in C::VM_METHOD_TYPE_ATTRSET
        jit_call_attrset(jit, ctx, asm, cme, calling, comptime_recv, recv_opnd)
      in C::VM_METHOD_TYPE_IVAR
        jit_call_ivar(jit, ctx, asm, cme, calling, comptime_recv, recv_opnd)
      in C::VM_METHOD_TYPE_MISSING
        asm.incr_counter(:send_missing)
        return CantCompile
      in C::VM_METHOD_TYPE_BMETHOD
        jit_call_bmethod(jit, ctx, asm, calling, cme, comptime_recv, recv_opnd, known_recv_class)
      in C::VM_METHOD_TYPE_ALIAS
        jit_call_alias(jit, ctx, asm, calling, cme, comptime_recv, recv_opnd, known_recv_class)
      in C::VM_METHOD_TYPE_OPTIMIZED
        jit_call_optimized(jit, ctx, asm, cme, calling, known_recv_class)
      in C::VM_METHOD_TYPE_UNDEF
        asm.incr_counter(:send_undef)
        return CantCompile
      in C::VM_METHOD_TYPE_ZSUPER
        asm.incr_counter(:send_zsuper)
        return CantCompile
      in C::VM_METHOD_TYPE_REFINED
        asm.incr_counter(:send_refined)
        return CantCompile
      end
    end

    # vm_call_iseq_setup
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_call_iseq(jit, ctx, asm, cme, calling, iseq, frame_type: nil, prev_ep: nil)
      argc = calling.argc
      flags = calling.flags
      send_shift = calling.send_shift

      # When you have keyword arguments, there is an extra object that gets
      # placed on the stack the represents a bitmap of the keywords that were not
      # specified at the call site. We need to keep track of the fact that this
      # value is present on the stack in order to properly set up the callee's
      # stack pointer.
      doing_kw_call = iseq.body.param.flags.has_kw
      supplying_kws = flags & C::VM_CALL_KWARG != 0

      if flags & C::VM_CALL_TAILCALL != 0
        # We can't handle tailcalls
        asm.incr_counter(:send_tailcall)
        return CantCompile
      end

      # No support for callees with these parameters yet as they require allocation
      # or complex handling.
      if iseq.body.param.flags.has_post
        asm.incr_counter(:send_iseq_has_opt)
        return CantCompile
      end
      if iseq.body.param.flags.has_kwrest
        asm.incr_counter(:send_iseq_has_kwrest)
        return CantCompile
      end

      # In order to handle backwards compatibility between ruby 3 and 2
      # ruby2_keywords was introduced. It is called only on methods
      # with splat and changes they way they handle them.
      # We are just going to not compile these.
      # https://www.rubydoc.info/stdlib/core/Proc:ruby2_keywords
      if iseq.body.param.flags.ruby2_keywords && flags & C::VM_CALL_ARGS_SPLAT != 0
        asm.incr_counter(:send_iseq_ruby2_keywords)
        return CantCompile
      end

      iseq_has_rest = iseq.body.param.flags.has_rest
      if iseq_has_rest && calling.block_handler == :captured
        asm.incr_counter(:send_iseq_has_rest_and_captured)
        return CantCompile
      end

      if iseq_has_rest && iseq.body.param.flags.has_kw && supplying_kws
        asm.incr_counter(:send_iseq_has_rest_and_kw_supplied)
        return CantCompile
      end

      # If we have keyword arguments being passed to a callee that only takes
      # positionals, then we need to allocate a hash. For now we're going to
      # call that too complex and bail.
      if supplying_kws && !iseq.body.param.flags.has_kw
        asm.incr_counter(:send_iseq_has_no_kw)
        return CantCompile
      end

      # If we have a method accepting no kwargs (**nil), exit if we have passed
      # it any kwargs.
      if supplying_kws && iseq.body.param.flags.accepts_no_kwarg
        asm.incr_counter(:send_iseq_accepts_no_kwarg)
        return CantCompile
      end

      # For computing number of locals to set up for the callee
      num_params = iseq.body.param.size

      # Block parameter handling. This mirrors setup_parameters_complex().
      if iseq.body.param.flags.has_block
        if iseq.body.local_iseq.to_i == iseq.to_i
          num_params -= 1
        else
          # In this case (param.flags.has_block && local_iseq != iseq),
          # the block argument is setup as a local variable and requires
          # materialization (allocation). Bail.
          asm.incr_counter(:send_iseq_materialized_block)
          return CantCompile
        end
      end

      if flags & C::VM_CALL_ARGS_SPLAT != 0 && flags & C::VM_CALL_ZSUPER != 0
        # zsuper methods are super calls without any arguments.
        # They are also marked as splat, but don't actually have an array
        # they pull arguments from, instead we need to change to call
        # a different method with the current stack.
        asm.incr_counter(:send_iseq_zsuper)
        return CantCompile
      end

      start_pc_offset = 0
      required_num = iseq.body.param.lead_num

      # This struct represents the metadata about the caller-specified
      # keyword arguments.
      kw_arg = calling.kwarg
      kw_arg_num = if kw_arg.nil?
        0
      else
        kw_arg.keyword_len
      end

      # Arity handling and optional parameter setup
      opts_filled = argc - required_num - kw_arg_num
      opt_num = iseq.body.param.opt_num
      opts_missing = opt_num - opts_filled

      if doing_kw_call && flags & C::VM_CALL_ARGS_SPLAT != 0
        asm.incr_counter(:send_iseq_splat_with_kw)
        return CantCompile
      end

      if iseq_has_rest && opt_num != 0
        asm.incr_counter(:send_iseq_has_rest_and_optional)
        return CantCompile
      end

      if opts_filled < 0 && flags & C::VM_CALL_ARGS_SPLAT == 0
        # Too few arguments and no splat to make up for it
        asm.incr_counter(:send_iseq_arity_error)
        return CantCompile
      end

      if opts_filled > opt_num && !iseq_has_rest
        # Too many arguments and no place to put them (i.e. rest arg)
        asm.incr_counter(:send_iseq_arity_error)
        return CantCompile
      end

      block_arg = flags & C::VM_CALL_ARGS_BLOCKARG != 0

      # Guard block_arg_type
      if guard_block_arg(jit, ctx, asm, calling) == CantCompile
        return CantCompile
      end

      # If we have unfilled optional arguments and keyword arguments then we
      # would need to adjust the arguments location to account for that.
      # For now we aren't handling this case.
      if doing_kw_call && opts_missing > 0
        asm.incr_counter(:send_iseq_missing_optional_kw)
        return CantCompile
      end

      # We will handle splat case later
      if opt_num > 0 && flags & C::VM_CALL_ARGS_SPLAT == 0
        num_params -= opts_missing
        start_pc_offset = iseq.body.param.opt_table[opts_filled]
      end

      if doing_kw_call
        # Here we're calling a method with keyword arguments and specifying
        # keyword arguments at this call site.

        # This struct represents the metadata about the callee-specified
        # keyword parameters.
        keyword = iseq.body.param.keyword
        keyword_num = keyword.num
        keyword_required_num = keyword.required_num

        required_kwargs_filled = 0

        if keyword_num > 30
          # We have so many keywords that (1 << num) encoded as a FIXNUM
          # (which shifts it left one more) no longer fits inside a 32-bit
          # immediate.
          asm.incr_counter(:send_iseq_too_many_kwargs)
          return CantCompile
        end

        # Check that the kwargs being passed are valid
        if supplying_kws
          # This is the list of keyword arguments that the callee specified
          # in its initial declaration.
          # SAFETY: see compile.c for sizing of this slice.
          callee_kwargs = keyword_num.times.map { |i| keyword.table[i] }

          # Here we're going to build up a list of the IDs that correspond to
          # the caller-specified keyword arguments. If they're not in the
          # same order as the order specified in the callee declaration, then
          # we're going to need to generate some code to swap values around
          # on the stack.
          caller_kwargs = []
          kw_arg.keyword_len.times do |kwarg_idx|
            sym = C.to_ruby(kw_arg[:keywords][kwarg_idx])
            caller_kwargs << C.rb_sym2id(sym)
          end

          # First, we're going to be sure that the names of every
          # caller-specified keyword argument correspond to a name in the
          # list of callee-specified keyword parameters.
          caller_kwargs.each do |caller_kwarg|
            search_result = callee_kwargs.map.with_index.find { |kwarg, _| kwarg == caller_kwarg }

            case search_result
            in nil
              # If the keyword was never found, then we know we have a
              # mismatch in the names of the keyword arguments, so we need to
              # bail.
              asm.incr_counter(:send_iseq_kwargs_mismatch)
              return CantCompile
            in _, callee_idx if callee_idx < keyword_required_num
              # Keep a count to ensure all required kwargs are specified
              required_kwargs_filled += 1
            else
            end
          end
        end
        assert_equal(true, required_kwargs_filled <= keyword_required_num)
        if required_kwargs_filled != keyword_required_num
          asm.incr_counter(:send_iseq_kwargs_mismatch)
          return CantCompile
        end
      end

      # Check if we need the arg0 splat handling of vm_callee_setup_block_arg
      arg_setup_block = (calling.block_handler == :captured) # arg_setup_type: arg_setup_block (invokeblock)
      block_arg0_splat = arg_setup_block && argc == 1 &&
        (iseq.body.param.flags.has_lead || opt_num > 1) &&
        !iseq.body.param.flags.ambiguous_param0
      if block_arg0_splat
        # If block_arg0_splat, we still need side exits after splat, but
        # doing push_splat_args here disallows it. So bail out.
        if flags & C::VM_CALL_ARGS_SPLAT != 0 && !iseq_has_rest
          asm.incr_counter(:invokeblock_iseq_arg0_args_splat)
          return CantCompile
        end
        # The block_arg0_splat implementation is for the rb_simple_iseq_p case,
        # but doing_kw_call means it's not a simple ISEQ.
        if doing_kw_call
          asm.incr_counter(:invokeblock_iseq_arg0_has_kw)
          return CantCompile
        end
        # The block_arg0_splat implementation cannot deal with optional parameters.
        # This is a setup_parameters_complex() situation and interacts with the
        # starting position of the callee.
        if opt_num > 1
          asm.incr_counter(:invokeblock_iseq_arg0_optional)
          return CantCompile
        end
      end
      if flags & C::VM_CALL_ARGS_SPLAT != 0 && !iseq_has_rest
        array = jit.peek_at_stack(block_arg ? 1 : 0)
        splat_array_length = if array.nil?
          0
        else
          array.length
        end

        if opt_num == 0 && required_num != splat_array_length + argc - 1
          asm.incr_counter(:send_iseq_splat_arity_error)
          return CantCompile
        end
      end

      # We will not have CantCompile from here.

      if block_arg
        ctx.stack_pop(1)
      end

      if calling.block_handler == C::VM_BLOCK_HANDLER_NONE && iseq.body.builtin_attrs & C::BUILTIN_ATTR_LEAF != 0
        if jit_leaf_builtin_func(jit, ctx, asm, flags, iseq)
          return KeepCompiling
        end
      end

      # Number of locals that are not parameters
      num_locals = iseq.body.local_table_size - num_params

      # Stack overflow check
      # Note that vm_push_frame checks it against a decremented cfp, hence the multiply by 2.
      # #define CHECK_VM_STACK_OVERFLOW0(cfp, sp, margin)
      asm.comment('stack overflow check')
      locals_offs = C.VALUE.size * (num_locals + iseq.body.stack_max) + 2 * C.rb_control_frame_t.size
      asm.lea(:rax, ctx.sp_opnd(locals_offs))
      asm.cmp(CFP, :rax)
      asm.jbe(counted_exit(side_exit(jit, ctx), :send_stackoverflow))

      # push_splat_args does stack manipulation so we can no longer side exit
      if splat_array_length
        remaining_opt = (opt_num + required_num) - (splat_array_length + (argc - 1))

        if opt_num > 0
          # We are going to jump to the correct offset based on how many optional
          # params are remaining.
          offset = opt_num - remaining_opt
          start_pc_offset = iseq.body.param.opt_table[offset]
        end
        # We are going to assume that the splat fills
        # all the remaining arguments. In the generated code
        # we test if this is true and if not side exit.
        argc = argc - 1 + splat_array_length + remaining_opt
        push_splat_args(splat_array_length, jit, ctx, asm)

        remaining_opt.times do
          # We need to push nil for the optional arguments
          stack_ret = ctx.stack_push(Type::Unknown)
          asm.mov(stack_ret, Qnil)
        end
      end

      # This is a .send call and we need to adjust the stack
      if flags & C::VM_CALL_OPT_SEND != 0
        handle_opt_send_shift_stack(asm, argc, ctx, send_shift:)
      end

      if iseq_has_rest
        # We are going to allocate so setting pc and sp.
        jit_save_pc(jit, asm) # clobbers rax
        jit_save_sp(ctx, asm)

        if flags & C::VM_CALL_ARGS_SPLAT != 0
          non_rest_arg_count = argc - 1
          # We start by dupping the array because someone else might have
          # a reference to it.
          array = ctx.stack_pop(1)
          asm.mov(C_ARGS[0], array)
          asm.call(C.rb_ary_dup)
          array = C_RET
          if non_rest_arg_count > required_num
            # If we have more arguments than required, we need to prepend
            # the items from the stack onto the array.
            diff = (non_rest_arg_count - required_num)

            # diff is >0 so no need to worry about null pointer
            asm.comment('load pointer to array elements')
            offset_magnitude = C.VALUE.size * diff
            values_opnd = ctx.sp_opnd(-offset_magnitude)
            values_ptr = :rcx
            asm.lea(values_ptr, values_opnd)

            asm.comment('prepend stack values to rest array')
            asm.mov(C_ARGS[0], diff)
            asm.mov(C_ARGS[1], values_ptr)
            asm.mov(C_ARGS[2], array)
            asm.call(C.rb_ary_unshift_m)
            ctx.stack_pop(diff)

            stack_ret = ctx.stack_push(Type::TArray)
            asm.mov(stack_ret, C_RET)
            # We now should have the required arguments
            # and an array of all the rest arguments
            argc = required_num + 1
          elsif non_rest_arg_count < required_num
            # If we have fewer arguments than required, we need to take some
            # from the array and move them to the stack.
            diff = (required_num - non_rest_arg_count)
            # This moves the arguments onto the stack. But it doesn't modify the array.
            move_rest_args_to_stack(array, diff, jit, ctx, asm)

            # We will now slice the array to give us a new array of the correct size
            asm.mov(C_ARGS[0], array)
            asm.mov(C_ARGS[1], diff)
            asm.call(C.rjit_rb_ary_subseq_length)
            stack_ret = ctx.stack_push(Type::TArray)
            asm.mov(stack_ret, C_RET)

            # We now should have the required arguments
            # and an array of all the rest arguments
            argc = required_num + 1
          else
            # The arguments are equal so we can just push to the stack
            assert_equal(non_rest_arg_count, required_num)
            stack_ret = ctx.stack_push(Type::TArray)
            asm.mov(stack_ret, array)
          end
        else
          assert_equal(true, argc >= required_num)
          n = (argc - required_num)
          argc = required_num + 1
          # If n is 0, then elts is never going to be read, so we can just pass null
          if n == 0
            values_ptr = 0
          else
            asm.comment('load pointer to array elements')
            offset_magnitude = C.VALUE.size * n
            values_opnd = ctx.sp_opnd(-offset_magnitude)
            values_ptr = :rcx
            asm.lea(values_ptr, values_opnd)
          end

          asm.mov(C_ARGS[0], EC)
          asm.mov(C_ARGS[1], n)
          asm.mov(C_ARGS[2], values_ptr)
          asm.call(C.rb_ec_ary_new_from_values)

          ctx.stack_pop(n)
          stack_ret = ctx.stack_push(Type::TArray)
          asm.mov(stack_ret, C_RET)
        end
      end

      if doing_kw_call
        # Here we're calling a method with keyword arguments and specifying
        # keyword arguments at this call site.

        # Number of positional arguments the callee expects before the first
        # keyword argument
        args_before_kw = required_num + opt_num

        # This struct represents the metadata about the caller-specified
        # keyword arguments.
        ci_kwarg = calling.kwarg
        caller_keyword_len = if ci_kwarg.nil?
          0
        else
          ci_kwarg.keyword_len
        end

        # This struct represents the metadata about the callee-specified
        # keyword parameters.
        keyword = iseq.body.param.keyword

        asm.comment('keyword args')

        # This is the list of keyword arguments that the callee specified
        # in its initial declaration.
        callee_kwargs = keyword.table
        total_kwargs = keyword.num

        # Here we're going to build up a list of the IDs that correspond to
        # the caller-specified keyword arguments. If they're not in the
        # same order as the order specified in the callee declaration, then
        # we're going to need to generate some code to swap values around
        # on the stack.
        caller_kwargs = []

        caller_keyword_len.times do |kwarg_idx|
          sym = C.to_ruby(ci_kwarg[:keywords][kwarg_idx])
          caller_kwargs << C.rb_sym2id(sym)
        end
        kwarg_idx = caller_keyword_len

        unspecified_bits = 0

        keyword_required_num = keyword.required_num
        (keyword_required_num...total_kwargs).each do |callee_idx|
          already_passed = false
          callee_kwarg = callee_kwargs[callee_idx]

          caller_keyword_len.times do |caller_idx|
            if caller_kwargs[caller_idx] == callee_kwarg
              already_passed = true
              break
            end
          end

          unless already_passed
            # Reserve space on the stack for each default value we'll be
            # filling in (which is done in the next loop). Also increments
            # argc so that the callee's SP is recorded correctly.
            argc += 1
            default_arg = ctx.stack_push(Type::Unknown)

            # callee_idx - keyword->required_num is used in a couple of places below.
            req_num = keyword.required_num
            extra_args = callee_idx - req_num

            # VALUE default_value = keyword->default_values[callee_idx - keyword->required_num];
            default_value = keyword.default_values[extra_args]

            if default_value == Qundef
              # Qundef means that this value is not constant and must be
              # recalculated at runtime, so we record it in unspecified_bits
              # (Qnil is then used as a placeholder instead of Qundef).
              unspecified_bits |= 0x01 << extra_args
              default_value = Qnil
            end

            asm.mov(:rax, default_value)
            asm.mov(default_arg, :rax)

            caller_kwargs[kwarg_idx] = callee_kwarg
            kwarg_idx += 1
          end
        end

        assert_equal(kwarg_idx, total_kwargs)

        # Next, we're going to loop through every keyword that was
        # specified by the caller and make sure that it's in the correct
        # place. If it's not we're going to swap it around with another one.
        total_kwargs.times do |kwarg_idx|
          callee_kwarg = callee_kwargs[kwarg_idx]

          # If the argument is already in the right order, then we don't
          # need to generate any code since the expected value is already
          # in the right place on the stack.
          if callee_kwarg == caller_kwargs[kwarg_idx]
            next
          end

          # In this case the argument is not in the right place, so we
          # need to find its position where it _should_ be and swap with
          # that location.
          ((kwarg_idx + 1)...total_kwargs).each do |swap_idx|
            if callee_kwarg == caller_kwargs[swap_idx]
              # First we're going to generate the code that is going
              # to perform the actual swapping at runtime.
              offset0 = argc - 1 - swap_idx - args_before_kw
              offset1 = argc - 1 - kwarg_idx - args_before_kw
              stack_swap(jit, ctx, asm, offset0, offset1)

              # Next we're going to do some bookkeeping on our end so
              # that we know the order that the arguments are
              # actually in now.
              caller_kwargs[kwarg_idx], caller_kwargs[swap_idx] =
                caller_kwargs[swap_idx], caller_kwargs[kwarg_idx]

              break
            end
          end
        end

        # Keyword arguments cause a special extra local variable to be
        # pushed onto the stack that represents the parameters that weren't
        # explicitly given a value and have a non-constant default.
        asm.mov(ctx.stack_opnd(-1), C.to_value(unspecified_bits))
      end

      # Same as vm_callee_setup_block_arg_arg0_check and vm_callee_setup_block_arg_arg0_splat
      # on vm_callee_setup_block_arg for arg_setup_block. This is done after CALLER_SETUP_ARG
      # and CALLER_REMOVE_EMPTY_KW_SPLAT, so this implementation is put here. This may need
      # side exits, so you still need to allow side exits here if block_arg0_splat is true.
      # Note that you can't have side exits after this arg0 splat.
      if block_arg0_splat
        asm.incr_counter(:send_iseq_block_arg0_splat)
        return CantCompile
      end

      # Create a context for the callee
      callee_ctx = Context.new

      # Set the argument types in the callee's context
      argc.times do |arg_idx|
        stack_offs = argc - arg_idx - 1
        arg_type = ctx.get_opnd_type(StackOpnd[stack_offs])
        callee_ctx.set_local_type(arg_idx, arg_type)
      end

      recv_type = if calling.block_handler == :captured
        Type::Unknown # we don't track the type information of captured->self for now
      else
        ctx.get_opnd_type(StackOpnd[argc])
      end
      callee_ctx.upgrade_opnd_type(SelfOpnd, recv_type)

      # Setup the new frame
      frame_type ||= C::VM_FRAME_MAGIC_METHOD | C::VM_ENV_FLAG_LOCAL
      jit_push_frame(
        jit, ctx, asm, cme, flags, argc, frame_type, calling.block_handler,
        iseq:       iseq,
        local_size: num_locals,
        stack_max:  iseq.body.stack_max,
        prev_ep:,
        doing_kw_call:,
      )

      # Directly jump to the entry point of the callee
      pc = (iseq.body.iseq_encoded + start_pc_offset).to_i
      jit_direct_jump(iseq, pc, callee_ctx, asm)

      EndBlock
    end

    def jit_leaf_builtin_func(jit, ctx, asm, flags, iseq)
      builtin_func = builtin_function(iseq)
      if builtin_func.nil?
        return false
      end

      # this is a .send call not currently supported for builtins
      if flags & C::VM_CALL_OPT_SEND != 0
        return false
      end

      builtin_argc = builtin_func.argc
      if builtin_argc + 1 >= C_ARGS.size
        return false
      end

      asm.comment('inlined leaf builtin')

      # Skip this if it doesn't trigger GC
      if iseq.body.builtin_attrs & C::BUILTIN_ATTR_NO_GC == 0
        # The callee may allocate, e.g. Integer#abs on a Bignum.
        # Save SP for GC, save PC for allocation tracing, and prepare
        # for global invalidation after GC's VM lock contention.
        jit_prepare_routine_call(jit, ctx, asm)
      end

      # Call the builtin func (ec, recv, arg1, arg2, ...)
      asm.mov(C_ARGS[0], EC)

      # Copy self and arguments
      (0..builtin_argc).each do |i|
        stack_opnd = ctx.stack_opnd(builtin_argc - i)
        asm.mov(C_ARGS[i + 1], stack_opnd)
      end
      ctx.stack_pop(builtin_argc + 1)
      asm.call(builtin_func.func_ptr)

      # Push the return value
      stack_ret = ctx.stack_push(Type::Unknown)
      asm.mov(stack_ret, C_RET)
      return true
    end

    # vm_call_cfunc
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_call_cfunc(jit, ctx, asm, cme, calling, known_recv_class: nil)
      argc = calling.argc
      flags = calling.flags

      cfunc = cme.def.body.cfunc
      cfunc_argc = cfunc.argc

      # If the function expects a Ruby array of arguments
      if cfunc_argc < 0 && cfunc_argc != -1
        asm.incr_counter(:send_cfunc_ruby_array_varg)
        return CantCompile
      end

      # We aren't handling a vararg cfuncs with splat currently.
      if flags & C::VM_CALL_ARGS_SPLAT != 0 && cfunc_argc == -1
        asm.incr_counter(:send_args_splat_cfunc_var_args)
        return CantCompile
      end

      if flags & C::VM_CALL_ARGS_SPLAT != 0 && flags & C::VM_CALL_ZSUPER != 0
        # zsuper methods are super calls without any arguments.
        # They are also marked as splat, but don't actually have an array
        # they pull arguments from, instead we need to change to call
        # a different method with the current stack.
        asm.incr_counter(:send_args_splat_cfunc_zuper)
        return CantCompile;
      end

      # In order to handle backwards compatibility between ruby 3 and 2
      # ruby2_keywords was introduced. It is called only on methods
      # with splat and changes they way they handle them.
      # We are just going to not compile these.
      # https://docs.ruby-lang.org/en/3.2/Module.html#method-i-ruby2_keywords
      if jit.iseq.body.param.flags.ruby2_keywords && flags & C::VM_CALL_ARGS_SPLAT != 0
        asm.incr_counter(:send_args_splat_cfunc_ruby2_keywords)
        return CantCompile;
      end

      kw_arg = calling.kwarg
      kw_arg_num = if kw_arg.nil?
        0
      else
        kw_arg.keyword_len
      end

      if kw_arg_num != 0 && flags & C::VM_CALL_ARGS_SPLAT != 0
        asm.incr_counter(:send_cfunc_splat_with_kw)
        return CantCompile
      end

      if c_method_tracing_currently_enabled?
        # Don't JIT if tracing c_call or c_return
        asm.incr_counter(:send_cfunc_tracing)
        return CantCompile
      end

      # Delegate to codegen for C methods if we have it.
      if kw_arg.nil? && flags & C::VM_CALL_OPT_SEND == 0 && flags & C::VM_CALL_ARGS_SPLAT == 0 && (cfunc_argc == -1 || argc == cfunc_argc)
        known_cfunc_codegen = lookup_cfunc_codegen(cme.def)
        if known_cfunc_codegen&.call(jit, ctx, asm, argc, known_recv_class)
          # cfunc codegen generated code. Terminate the block so
          # there isn't multiple calls in the same block.
          jump_to_next_insn(jit, ctx, asm)
          return EndBlock
        end
      end

      # Check for interrupts
      jit_check_ints(jit, ctx, asm)

      # Stack overflow check
      # #define CHECK_VM_STACK_OVERFLOW0(cfp, sp, margin)
      # REG_CFP <= REG_SP + 4 * SIZEOF_VALUE + sizeof(rb_control_frame_t)
      asm.comment('stack overflow check')
      asm.lea(:rax, ctx.sp_opnd(C.VALUE.size * 4 + 2 * C.rb_control_frame_t.size))
      asm.cmp(CFP, :rax)
      asm.jbe(counted_exit(side_exit(jit, ctx), :send_stackoverflow))

      # Number of args which will be passed through to the callee
      # This is adjusted by the kwargs being combined into a hash.
      passed_argc = if kw_arg.nil?
        argc
      else
        argc - kw_arg_num + 1
      end

      # If the argument count doesn't match
      if cfunc_argc >= 0 && cfunc_argc != passed_argc && flags & C::VM_CALL_ARGS_SPLAT == 0
        asm.incr_counter(:send_cfunc_argc_mismatch)
        return CantCompile
      end

      # Don't JIT functions that need C stack arguments for now
      if cfunc_argc >= 0 && passed_argc + 1 > C_ARGS.size
        asm.incr_counter(:send_cfunc_toomany_args)
        return CantCompile
      end

      block_arg = flags & C::VM_CALL_ARGS_BLOCKARG != 0

      # Guard block_arg_type
      if guard_block_arg(jit, ctx, asm, calling) == CantCompile
        return CantCompile
      end

      if block_arg
        ctx.stack_pop(1)
      end

      # push_splat_args does stack manipulation so we can no longer side exit
      if flags & C::VM_CALL_ARGS_SPLAT != 0
        assert_equal(true, cfunc_argc >= 0)
        required_args = cfunc_argc - (argc - 1)
        # + 1 because we pass self
        if required_args + 1 >= C_ARGS.size
          asm.incr_counter(:send_cfunc_toomany_args)
          return CantCompile
        end

        # We are going to assume that the splat fills
        # all the remaining arguments. So the number of args
        # should just equal the number of args the cfunc takes.
        # In the generated code we test if this is true
        # and if not side exit.
        argc = cfunc_argc
        passed_argc = argc
        push_splat_args(required_args, jit, ctx, asm)
      end

      # This is a .send call and we need to adjust the stack
      if flags & C::VM_CALL_OPT_SEND != 0
        handle_opt_send_shift_stack(asm, argc, ctx, send_shift: calling.send_shift)
      end

      # Points to the receiver operand on the stack

      # Store incremented PC into current control frame in case callee raises.
      jit_save_pc(jit, asm)

      # Increment the stack pointer by 3 (in the callee)
      # sp += 3

      frame_type = C::VM_FRAME_MAGIC_CFUNC | C::VM_FRAME_FLAG_CFRAME | C::VM_ENV_FLAG_LOCAL
      if kw_arg
        frame_type |= C::VM_FRAME_FLAG_CFRAME_KW
      end

      jit_push_frame(jit, ctx, asm, cme, flags, argc, frame_type, calling.block_handler)

      if kw_arg
        # Build a hash from all kwargs passed
        asm.comment('build_kwhash')
        imemo_ci = calling.ci_addr
        # we assume all callinfos with kwargs are on the GC heap
        assert_equal(true, C.imemo_type_p(imemo_ci, C.imemo_callinfo))
        asm.mov(C_ARGS[0], imemo_ci)
        asm.lea(C_ARGS[1], ctx.sp_opnd(0))
        asm.call(C.rjit_build_kwhash)

        # Replace the stack location at the start of kwargs with the new hash
        stack_opnd = ctx.stack_opnd(argc - passed_argc)
        asm.mov(stack_opnd, C_RET)
      end

      # Copy SP because REG_SP will get overwritten
      sp = :rax
      asm.lea(sp, ctx.sp_opnd(0))

      # Pop the C function arguments from the stack (in the caller)
      ctx.stack_pop(argc + 1)

      # Write interpreter SP into CFP.
      # Needed in case the callee yields to the block.
      jit_save_sp(ctx, asm)

      # Non-variadic method
      case cfunc_argc
      in (0..) # Non-variadic method
        # Copy the arguments from the stack to the C argument registers
        # self is the 0th argument and is at index argc from the stack top
        (0..passed_argc).each do |i|
          asm.mov(C_ARGS[i], [sp, -(argc + 1 - i) * C.VALUE.size])
        end
      in -1 # Variadic method: rb_f_puts(int argc, VALUE *argv, VALUE recv)
        # The method gets a pointer to the first argument
        # rb_f_puts(int argc, VALUE *argv, VALUE recv)
        asm.mov(C_ARGS[0], passed_argc)
        asm.lea(C_ARGS[1], [sp, -argc * C.VALUE.size]) # argv
        asm.mov(C_ARGS[2], [sp, -(argc + 1) * C.VALUE.size]) # recv
      end

      # Call the C function
      # VALUE ret = (cfunc->func)(recv, argv[0], argv[1]);
      # cfunc comes from compile-time cme->def, which we assume to be stable.
      # Invalidation logic is in yjit_method_lookup_change()
      asm.comment('call C function')
      asm.mov(:rax, cfunc.func)
      asm.call(:rax) # TODO: use rel32 if close enough

      # Record code position for TracePoint patching. See full_cfunc_return().
      Invariants.record_global_inval_patch(asm, full_cfunc_return)

      # Push the return value on the Ruby stack
      stack_ret = ctx.stack_push(Type::Unknown)
      asm.mov(stack_ret, C_RET)

      # Pop the stack frame (ec->cfp++)
      # Instead of recalculating, we can reuse the previous CFP, which is stored in a callee-saved
      # register
      asm.mov([EC, C.rb_execution_context_t.offsetof(:cfp)], CFP)

      # cfunc calls may corrupt types
      ctx.clear_local_types

      # Note: the return block of jit_call_iseq has ctx->sp_offset == 1
      # which allows for sharing the same successor.

      # Jump (fall through) to the call continuation block
      # We do this to end the current block after the call
      assert_equal(1, ctx.sp_offset)
      jump_to_next_insn(jit, ctx, asm)
      EndBlock
    end

    # vm_call_attrset
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_call_attrset(jit, ctx, asm, cme, calling, comptime_recv, recv_opnd)
      argc = calling.argc
      flags = calling.flags
      send_shift = calling.send_shift

      if flags & C::VM_CALL_ARGS_SPLAT != 0
        asm.incr_counter(:send_attrset_splat)
        return CantCompile
      end
      if flags & C::VM_CALL_KWARG != 0
        asm.incr_counter(:send_attrset_kwarg)
        return CantCompile
      elsif argc != 1 || !C.RB_TYPE_P(comptime_recv, C::RUBY_T_OBJECT)
        asm.incr_counter(:send_attrset_method)
        return CantCompile
      elsif c_method_tracing_currently_enabled?
        # Can't generate code for firing c_call and c_return events
        # See :attr-tracing:
        asm.incr_counter(:send_c_tracingg)
        return CantCompile
      elsif flags & C::VM_CALL_ARGS_BLOCKARG != 0
        asm.incr_counter(:send_block_arg)
        return CantCompile
      end

      ivar_name = cme.def.body.attr.id

      # This is a .send call and we need to adjust the stack
      if flags & C::VM_CALL_OPT_SEND != 0
        handle_opt_send_shift_stack(asm, argc, ctx, send_shift:)
      end

      # Save the PC and SP because the callee may allocate
      # Note that this modifies REG_SP, which is why we do it first
      jit_prepare_routine_call(jit, ctx, asm)

      # Get the operands from the stack
      val_opnd = ctx.stack_pop(1)
      recv_opnd = ctx.stack_pop(1)

      # Call rb_vm_set_ivar_id with the receiver, the ivar name, and the value
      asm.mov(C_ARGS[0], recv_opnd)
      asm.mov(C_ARGS[1], ivar_name)
      asm.mov(C_ARGS[2], val_opnd)
      asm.call(C.rb_vm_set_ivar_id)

      out_opnd = ctx.stack_push(Type::Unknown)
      asm.mov(out_opnd, C_RET)

      KeepCompiling
    end

    # vm_call_ivar (+ part of vm_call_method_each_type)
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_call_ivar(jit, ctx, asm, cme, calling, comptime_recv, recv_opnd)
      argc = calling.argc
      flags = calling.flags

      if flags & C::VM_CALL_ARGS_SPLAT != 0
        asm.incr_counter(:send_ivar_splat)
        return CantCompile
      end

      if argc != 0
        asm.incr_counter(:send_arity)
        return CantCompile
      end

      # We don't support handle_opt_send_shift_stack for this yet.
      if flags & C::VM_CALL_OPT_SEND != 0
        asm.incr_counter(:send_ivar_opt_send)
        return CantCompile
      end

      ivar_id = cme.def.body.attr.id

      # Not handling block_handler
      if flags & C::VM_CALL_ARGS_BLOCKARG != 0
        asm.incr_counter(:send_block_arg)
        return CantCompile
      end

      jit_getivar(jit, ctx, asm, comptime_recv, ivar_id, recv_opnd, StackOpnd[0])
    end

    # vm_call_bmethod
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_call_bmethod(jit, ctx, asm, calling, cme, comptime_recv, recv_opnd, known_recv_class)
      proc_addr = cme.def.body.bmethod.proc

      proc_t = C.rb_yjit_get_proc_ptr(proc_addr)
      proc_block = proc_t.block

      if proc_block.type != C.block_type_iseq
        asm.incr_counter(:send_bmethod_not_iseq)
        return CantCompile
      end

      capture = proc_block.as.captured
      iseq = capture.code.iseq

      # TODO: implement this
      # Optimize for single ractor mode and avoid runtime check for
      # "defined with an un-shareable Proc in a different Ractor"
      # if !assume_single_ractor_mode(jit, ocb)
      #     return CantCompile;
      # end

      # Passing a block to a block needs logic different from passing
      # a block to a method and sometimes requires allocation. Bail for now.
      if calling.block_handler != C::VM_BLOCK_HANDLER_NONE
        asm.incr_counter(:send_bmethod_blockarg)
        return CantCompile
      end

      jit_call_iseq(
        jit, ctx, asm, cme, calling, iseq,
        frame_type: C::VM_FRAME_MAGIC_BLOCK | C::VM_FRAME_FLAG_BMETHOD | C::VM_FRAME_FLAG_LAMBDA,
        prev_ep: capture.ep,
      )
    end

    # vm_call_alias
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_call_alias(jit, ctx, asm, calling, cme, comptime_recv, recv_opnd, known_recv_class)
      cme = C.rb_aliased_callable_method_entry(cme)
      jit_call_method_each_type(jit, ctx, asm, calling, cme, comptime_recv, recv_opnd, known_recv_class)
    end

    # vm_call_optimized
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_call_optimized(jit, ctx, asm, cme, calling, known_recv_class)
      if calling.flags & C::VM_CALL_ARGS_BLOCKARG != 0
        # Not working yet
        asm.incr_counter(:send_block_arg)
        return CantCompile
      end

      case cme.def.body.optimized.type
      in C::OPTIMIZED_METHOD_TYPE_SEND
        jit_call_opt_send(jit, ctx, asm, cme, calling, known_recv_class)
      in C::OPTIMIZED_METHOD_TYPE_CALL
        jit_call_opt_call(jit, ctx, asm, cme, calling.flags, calling.argc, calling.block_handler, known_recv_class, send_shift: calling.send_shift)
      in C::OPTIMIZED_METHOD_TYPE_BLOCK_CALL
        asm.incr_counter(:send_optimized_block_call)
        return CantCompile
      in C::OPTIMIZED_METHOD_TYPE_STRUCT_AREF
        jit_call_opt_struct_aref(jit, ctx, asm, cme, calling.flags, calling.argc, calling.block_handler, known_recv_class, send_shift: calling.send_shift)
      in C::OPTIMIZED_METHOD_TYPE_STRUCT_ASET
        asm.incr_counter(:send_optimized_struct_aset)
        return CantCompile
      end
    end

    # vm_call_opt_send
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_call_opt_send(jit, ctx, asm, cme, calling, known_recv_class)
      if jit_caller_setup_arg(jit, ctx, asm, calling.flags) == CantCompile
        return CantCompile
      end

      if calling.argc == 0
        asm.incr_counter(:send_optimized_send_no_args)
        return CantCompile
      end

      calling.argc -= 1
      # We aren't handling `send(:send, ...)` yet. This might work, but not tested yet.
      if calling.send_shift > 0
        asm.incr_counter(:send_optimized_send_send)
        return CantCompile
      end
      # Lazily handle stack shift in handle_opt_send_shift_stack
      calling.send_shift += 1

      jit_call_symbol(jit, ctx, asm, cme, calling, known_recv_class, C::VM_CALL_FCALL)
    end

    # vm_call_opt_call
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_call_opt_call(jit, ctx, asm, cme, flags, argc, block_handler, known_recv_class, send_shift:)
      if block_handler != C::VM_BLOCK_HANDLER_NONE
        asm.incr_counter(:send_optimized_call_block)
        return CantCompile
      end

      if flags & C::VM_CALL_KWARG != 0
        asm.incr_counter(:send_optimized_call_kwarg)
        return CantCompile
      end

      if flags & C::VM_CALL_ARGS_SPLAT != 0
        asm.incr_counter(:send_optimized_call_splat)
        return CantCompile
      end

      # TODO: implement this
      # Optimize for single ractor mode and avoid runtime check for
      # "defined with an un-shareable Proc in a different Ractor"
      # if !assume_single_ractor_mode(jit, ocb)
      #   return CantCompile
      # end

      # If this is a .send call we need to adjust the stack
      if flags & C::VM_CALL_OPT_SEND != 0
        handle_opt_send_shift_stack(asm, argc, ctx, send_shift:)
      end

      # About to reset the SP, need to load this here
      recv_idx = argc # blockarg is not supported. send_shift is already handled.
      asm.mov(:rcx, ctx.stack_opnd(recv_idx)) # recv

      # Save the PC and SP because the callee can make Ruby calls
      jit_prepare_routine_call(jit, ctx, asm) # NOTE: clobbers rax

      asm.lea(:rax, ctx.sp_opnd(0)) # sp

      kw_splat = flags & C::VM_CALL_KW_SPLAT

      asm.mov(C_ARGS[0], :rcx)
      asm.mov(C_ARGS[1], EC)
      asm.mov(C_ARGS[2], argc)
      asm.lea(C_ARGS[3], [:rax, -argc * C.VALUE.size]) # stack_argument_pointer. NOTE: C_ARGS[3] is rcx
      asm.mov(C_ARGS[4], kw_splat)
      asm.mov(C_ARGS[5], C::VM_BLOCK_HANDLER_NONE)
      asm.call(C.rjit_optimized_call)

      ctx.stack_pop(argc + 1)

      stack_ret = ctx.stack_push(Type::Unknown)
      asm.mov(stack_ret, C_RET)
      return KeepCompiling
    end

    # vm_call_opt_struct_aref
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_call_opt_struct_aref(jit, ctx, asm, cme, flags, argc, block_handler, known_recv_class, send_shift:)
      if argc != 0
        asm.incr_counter(:send_optimized_struct_aref_error)
        return CantCompile
      end

      off = cme.def.body.optimized.index

      recv_idx = argc # blockarg is not supported
      recv_idx += send_shift
      comptime_recv = jit.peek_at_stack(recv_idx)

      # This is a .send call and we need to adjust the stack
      if flags & C::VM_CALL_OPT_SEND != 0
        handle_opt_send_shift_stack(asm, argc, ctx, send_shift:)
      end

      # All structs from the same Struct class should have the same
      # length. So if our comptime_recv is embedded all runtime
      # structs of the same class should be as well, and the same is
      # true of the converse.
      embedded = C::FL_TEST_RAW(comptime_recv, C::RSTRUCT_EMBED_LEN_MASK)

      asm.comment('struct aref')
      asm.mov(:rax, ctx.stack_pop(1)) # recv

      if embedded
        asm.mov(:rax, [:rax, C.RStruct.offsetof(:as, :ary) + (C.VALUE.size * off)])
      else
        asm.mov(:rax, [:rax, C.RStruct.offsetof(:as, :heap, :ptr)])
        asm.mov(:rax, [:rax, C.VALUE.size * off])
      end

      ret = ctx.stack_push(Type::Unknown)
      asm.mov(ret, :rax)

      jump_to_next_insn(jit, ctx, asm)
      EndBlock
    end

    # vm_call_opt_send (lazy part)
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def handle_opt_send_shift_stack(asm, argc, ctx, send_shift:)
      # We don't support `send(:send, ...)` for now.
      assert_equal(1, send_shift)

      asm.comment('shift stack')
      (0...argc).reverse_each do |i|
        opnd = ctx.stack_opnd(i)
        opnd2 = ctx.stack_opnd(i + 1)
        asm.mov(:rax, opnd)
        asm.mov(opnd2, :rax)
      end

      ctx.shift_stack(argc)
    end

    # vm_call_symbol
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_call_symbol(jit, ctx, asm, cme, calling, known_recv_class, flags)
      flags |= C::VM_CALL_OPT_SEND | (calling.kw_splat ? C::VM_CALL_KW_SPLAT : 0)

      comptime_symbol = jit.peek_at_stack(calling.argc)
      if comptime_symbol.class != String && !static_symbol?(comptime_symbol)
        asm.incr_counter(:send_optimized_send_not_sym_or_str)
        return CantCompile
      end

      mid = C.get_symbol_id(comptime_symbol)
      if mid == 0
        asm.incr_counter(:send_optimized_send_null_mid)
        return CantCompile
      end

      asm.comment("Guard #{comptime_symbol.inspect} is on stack")
      class_changed_exit = counted_exit(side_exit(jit, ctx), :send_optimized_send_mid_class_changed)
      jit_guard_known_klass(
        jit, ctx, asm, C.rb_class_of(comptime_symbol), ctx.stack_opnd(calling.argc),
        StackOpnd[calling.argc], comptime_symbol, class_changed_exit,
      )
      asm.mov(C_ARGS[0], ctx.stack_opnd(calling.argc))
      asm.call(C.rb_get_symbol_id)
      asm.cmp(C_RET, mid)
      id_changed_exit = counted_exit(side_exit(jit, ctx), :send_optimized_send_mid_id_changed)
      jit_chain_guard(:jne, jit, ctx, asm, id_changed_exit)

      # rb_callable_method_entry_with_refinements
      calling.flags = flags
      cme, _ = jit_search_method(jit, ctx, asm, mid, calling)
      if cme == CantCompile
        return CantCompile
      end

      if flags & C::VM_CALL_FCALL != 0
        return jit_call_method(jit, ctx, asm, mid, calling, cme, known_recv_class)
      end

      raise NotImplementedError # unreachable for now
    end

    # vm_push_frame
    #
    # Frame structure:
    # | args | locals | cme/cref | block_handler/prev EP | frame type (EP here) | stack bottom (SP here)
    #
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_push_frame(jit, ctx, asm, cme, flags, argc, frame_type, block_handler, iseq: nil, local_size: 0, stack_max: 0, prev_ep: nil, doing_kw_call: nil)
      # Save caller SP and PC before pushing a callee frame for backtrace and side exits
      asm.comment('save SP to caller CFP')
      recv_idx = argc # blockarg is already popped
      recv_idx += (block_handler == :captured) ? 0 : 1 # receiver is not on stack when captured->self is used
      if iseq
        # Skip setting this to SP register. This cfp->sp will be copied to SP on leave insn.
        asm.lea(:rax, ctx.sp_opnd(C.VALUE.size * -recv_idx)) # Pop receiver and arguments to prepare for side exits
        asm.mov([CFP, C.rb_control_frame_t.offsetof(:sp)], :rax)
      else
        asm.lea(SP, ctx.sp_opnd(C.VALUE.size * -recv_idx))
        asm.mov([CFP, C.rb_control_frame_t.offsetof(:sp)], SP)
        ctx.sp_offset = recv_idx
      end
      jit_save_pc(jit, asm, comment: 'save PC to caller CFP')

      sp_offset = ctx.sp_offset + 3 + local_size + (doing_kw_call ? 1 : 0) # callee_sp
      local_size.times do |i|
        asm.comment('set local variables') if i == 0
        local_index = sp_offset + i - local_size - 3
        asm.mov([SP, C.VALUE.size * local_index], Qnil)
      end

      asm.comment('set up EP with managing data')
      ep_offset = sp_offset - 1
      # ep[-2]: cref_or_me
      asm.mov(:rax, cme.to_i)
      asm.mov([SP, C.VALUE.size * (ep_offset - 2)], :rax)
      # ep[-1]: block handler or prev env ptr (specval)
      if prev_ep
        asm.mov(:rax, prev_ep.to_i | 1) # tagged prev ep
        asm.mov([SP, C.VALUE.size * (ep_offset - 1)], :rax)
      elsif block_handler == :captured
        # Set captured->ep, saving captured in :rcx for captured->self
        ep_reg = :rcx
        jit_get_lep(jit, asm, reg: ep_reg)
        asm.mov(:rcx, [ep_reg, C.VALUE.size * C::VM_ENV_DATA_INDEX_SPECVAL]) # block_handler
        asm.and(:rcx, ~0x3) # captured
        asm.mov(:rax, [:rcx, C.VALUE.size]) # captured->ep
        asm.or(:rax, 0x1) # GC_GUARDED_PTR
        asm.mov([SP, C.VALUE.size * (ep_offset - 1)], :rax)
      elsif block_handler == C::VM_BLOCK_HANDLER_NONE
        asm.mov([SP, C.VALUE.size * (ep_offset - 1)], C::VM_BLOCK_HANDLER_NONE)
      elsif block_handler == C.rb_block_param_proxy
        # vm_caller_setup_arg_block: block_code == rb_block_param_proxy
        jit_get_lep(jit, asm, reg: :rax) # VM_CF_BLOCK_HANDLER: VM_CF_LEP
        asm.mov(:rax, [:rax, C.VALUE.size * C::VM_ENV_DATA_INDEX_SPECVAL]) # VM_CF_BLOCK_HANDLER: VM_ENV_BLOCK_HANDLER
        asm.mov([CFP, C.rb_control_frame_t.offsetof(:block_code)], :rax) # reg_cfp->block_code = handler
        asm.mov([SP, C.VALUE.size * (ep_offset - 1)], :rax) # return handler;
      else # assume blockiseq
        asm.mov(:rax, block_handler)
        asm.mov([CFP, C.rb_control_frame_t.offsetof(:block_code)], :rax)
        asm.lea(:rax, [CFP, C.rb_control_frame_t.offsetof(:self)]) # VM_CFP_TO_CAPTURED_BLOCK
        asm.or(:rax, 1) # VM_BH_FROM_ISEQ_BLOCK
        asm.mov([SP, C.VALUE.size * (ep_offset - 1)], :rax)
      end
      # ep[-0]: ENV_FLAGS
      asm.mov([SP, C.VALUE.size * (ep_offset - 0)], frame_type)

      asm.comment('set up new frame')
      cfp_offset = -C.rb_control_frame_t.size # callee CFP
      # For ISEQ, JIT code will set it as needed. However, C func needs 0 there for svar frame detection.
      if iseq.nil?
        asm.mov([CFP, cfp_offset + C.rb_control_frame_t.offsetof(:pc)], 0)
      end
      asm.mov(:rax, iseq.to_i)
      asm.mov([CFP, cfp_offset + C.rb_control_frame_t.offsetof(:iseq)], :rax)
      if block_handler == :captured
        asm.mov(:rax, [:rcx]) # captured->self
      else
        self_index = ctx.sp_offset - (1 + argc) # blockarg has been popped
        asm.mov(:rax, [SP, C.VALUE.size * self_index])
      end
      asm.mov([CFP, cfp_offset + C.rb_control_frame_t.offsetof(:self)], :rax)
      asm.lea(:rax, [SP, C.VALUE.size * ep_offset])
      asm.mov([CFP, cfp_offset + C.rb_control_frame_t.offsetof(:ep)], :rax)
      asm.mov([CFP, cfp_offset + C.rb_control_frame_t.offsetof(:block_code)], 0)
      # Update SP register only for ISEQ calls. SP-relative operations should be done above this.
      sp_reg = iseq ? SP : :rax
      asm.lea(sp_reg, [SP, C.VALUE.size * sp_offset])
      asm.mov([CFP, cfp_offset + C.rb_control_frame_t.offsetof(:sp)], sp_reg)

      # cfp->jit_return is used only for ISEQs
      if iseq
        # The callee might change locals through Kernel#binding and other means.
        ctx.clear_local_types

        # Stub cfp->jit_return
        return_ctx = ctx.dup
        return_ctx.stack_pop(argc + ((block_handler == :captured) ? 0 : 1)) # Pop args and receiver. blockarg has been popped
        return_ctx.stack_push(Type::Unknown) # push callee's return value
        return_ctx.sp_offset = 1 # SP is in the position after popping a receiver and arguments
        return_ctx.chain_depth = 0
        branch_stub = BranchStub.new(
          iseq: jit.iseq,
          shape: Default,
          target0: BranchTarget.new(ctx: return_ctx, pc: jit.pc + jit.insn.len * C.VALUE.size),
        )
        branch_stub.target0.address = Assembler.new.then do |ocb_asm|
          @exit_compiler.compile_branch_stub(return_ctx, ocb_asm, branch_stub, true)
          @ocb.write(ocb_asm)
        end
        branch_stub.compile = compile_jit_return(branch_stub, cfp_offset:)
        branch_stub.compile.call(asm)
      end

      asm.comment('switch to callee CFP')
      # Update CFP register only for ISEQ calls
      cfp_reg = iseq ? CFP : :rax
      asm.lea(cfp_reg, [CFP, cfp_offset])
      asm.mov([EC, C.rb_execution_context_t.offsetof(:cfp)], cfp_reg)
    end

    def compile_jit_return(branch_stub, cfp_offset:) # Proc escapes arguments in memory
      proc do |branch_asm|
        branch_asm.comment('set jit_return to callee CFP')
        branch_asm.stub(branch_stub) do
          case branch_stub.shape
          in Default
            branch_asm.mov(:rax, branch_stub.target0.address)
            branch_asm.mov([CFP, cfp_offset + C.rb_control_frame_t.offsetof(:jit_return)], :rax)
          end
        end
      end
    end

    # CALLER_SETUP_ARG: Return CantCompile if not supported
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def jit_caller_setup_arg(jit, ctx, asm, flags)
      if flags & C::VM_CALL_ARGS_SPLAT != 0 && flags & C::VM_CALL_KW_SPLAT != 0
        asm.incr_counter(:send_args_splat_kw_splat)
        return CantCompile
      elsif flags & C::VM_CALL_ARGS_SPLAT != 0
        # splat is not supported in this path
        asm.incr_counter(:send_args_splat)
        return CantCompile
      elsif flags & C::VM_CALL_KW_SPLAT != 0
        asm.incr_counter(:send_args_kw_splat)
        return CantCompile
      elsif flags & C::VM_CALL_KWARG != 0
        asm.incr_counter(:send_kwarg)
        return CantCompile
      end
    end

    # Pushes arguments from an array to the stack. Differs from push splat because
    # the array can have items left over.
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def move_rest_args_to_stack(array, num_args, jit, ctx, asm)
      side_exit = side_exit(jit, ctx)

      asm.comment('move_rest_args_to_stack')

      # array is :rax
      array_len_opnd = :rcx
      jit_array_len(asm, array, array_len_opnd)

      asm.comment('Side exit if length is less than required')
      asm.cmp(array_len_opnd, num_args)
      asm.jl(counted_exit(side_exit, :send_iseq_has_rest_and_splat_not_equal))

      asm.comment('Push arguments from array')

      # Load the address of the embedded array
      # (struct RArray *)(obj)->as.ary
      array_reg = array

      # Conditionally load the address of the heap array
      # (struct RArray *)(obj)->as.heap.ptr
      flags_opnd = [array_reg, C.RBasic.offsetof(:flags)]
      asm.test(flags_opnd, C::RARRAY_EMBED_FLAG)
      heap_ptr_opnd = [array_reg, C.RArray.offsetof(:as, :heap, :ptr)]
      # Load the address of the embedded array
      # (struct RArray *)(obj)->as.ary
      ary_opnd = :rdx # NOTE: array :rax is used after move_rest_args_to_stack too
      asm.lea(:rcx, [array_reg, C.RArray.offsetof(:as, :ary)])
      asm.mov(ary_opnd, heap_ptr_opnd)
      asm.cmovnz(ary_opnd, :rcx)

      num_args.times do |i|
        top = ctx.stack_push(Type::Unknown)
        asm.mov(:rcx, [ary_opnd, i * C.VALUE.size])
        asm.mov(top, :rcx)
      end
    end

    # vm_caller_setup_arg_splat (+ CALLER_SETUP_ARG):
    # Pushes arguments from an array to the stack that are passed with a splat (i.e. *args).
    # It optimistically compiles to a static size that is the exact number of arguments needed for the function.
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def push_splat_args(required_args, jit, ctx, asm)
      side_exit = side_exit(jit, ctx)

      asm.comment('push_splat_args')

      array_opnd = ctx.stack_opnd(0)
      array_stack_opnd = StackOpnd[0]
      array_reg = :rax
      asm.mov(array_reg, array_opnd)

      guard_object_is_array(jit, ctx, asm, array_reg, :rcx, array_stack_opnd, :send_args_splat_not_array)

      array_len_opnd = :rcx
      jit_array_len(asm, array_reg, array_len_opnd)

      asm.comment('Side exit if length is not equal to remaining args')
      asm.cmp(array_len_opnd, required_args)
      asm.jne(counted_exit(side_exit, :send_args_splat_length_not_equal))

      asm.comment('Check last argument is not ruby2keyword hash')

      ary_opnd = :rcx
      jit_array_ptr(asm, array_reg, ary_opnd) # clobbers array_reg

      last_array_value = :rax
      asm.mov(last_array_value, [ary_opnd, (required_args - 1) * C.VALUE.size])

      ruby2_exit = counted_exit(side_exit, :send_args_splat_ruby2_hash);
      guard_object_is_not_ruby2_keyword_hash(asm, last_array_value, :rcx, ruby2_exit) # clobbers :rax

      asm.comment('Push arguments from array')
      array_opnd = ctx.stack_pop(1)

      if required_args > 0
        # Load the address of the embedded array
        # (struct RArray *)(obj)->as.ary
        array_reg = :rax
        asm.mov(array_reg, array_opnd)

        # Conditionally load the address of the heap array
        # (struct RArray *)(obj)->as.heap.ptr
        flags_opnd = [array_reg, C.RBasic.offsetof(:flags)]
        asm.test(flags_opnd, C::RARRAY_EMBED_FLAG)
        heap_ptr_opnd = [array_reg, C.RArray.offsetof(:as, :heap, :ptr)]
        # Load the address of the embedded array
        # (struct RArray *)(obj)->as.ary
        asm.lea(:rcx, [array_reg, C.RArray.offsetof(:as, :ary)])
        asm.mov(:rax, heap_ptr_opnd)
        asm.cmovnz(:rax, :rcx)
        ary_opnd = :rax

        (0...required_args).each do |i|
          top = ctx.stack_push(Type::Unknown)
          asm.mov(:rcx, [ary_opnd, i * C.VALUE.size])
          asm.mov(top, :rcx)
        end

        asm.comment('end push_each')
      end
    end

    # Generate RARRAY_LEN. For array_opnd, use Opnd::Reg to reduce memory access,
    # and use Opnd::Mem to save registers.
    def jit_array_len(asm, array_reg, len_reg)
      asm.comment('get array length for embedded or heap')

      # Pull out the embed flag to check if it's an embedded array.
      asm.mov(len_reg, [array_reg, C.RBasic.offsetof(:flags)])

      # Get the length of the array
      asm.and(len_reg, C::RARRAY_EMBED_LEN_MASK)
      asm.sar(len_reg, C::RARRAY_EMBED_LEN_SHIFT)

      # Conditionally move the length of the heap array
      asm.test([array_reg, C.RBasic.offsetof(:flags)], C::RARRAY_EMBED_FLAG)

      # Select the array length value
      asm.cmovz(len_reg, [array_reg, C.RArray.offsetof(:as, :heap, :len)])
    end

    # Generate RARRAY_CONST_PTR (part of RARRAY_AREF)
    def jit_array_ptr(asm, array_reg, ary_opnd) # clobbers array_reg
      asm.comment('get array pointer for embedded or heap')

      flags_opnd = [array_reg, C.RBasic.offsetof(:flags)]
      asm.test(flags_opnd, C::RARRAY_EMBED_FLAG)
      # Load the address of the embedded array
      # (struct RArray *)(obj)->as.ary
      asm.mov(ary_opnd, [array_reg, C.RArray.offsetof(:as, :heap, :ptr)])
      asm.lea(array_reg, [array_reg, C.RArray.offsetof(:as, :ary)]) # clobbers array_reg
      asm.cmovnz(ary_opnd, array_reg)
    end

    def assert(cond)
      assert_equal(cond, true)
    end

    def assert_equal(left, right)
      if left != right
        raise "'#{left.inspect}' was not '#{right.inspect}'"
      end
    end

    def fixnum?(obj)
      (C.to_value(obj) & C::RUBY_FIXNUM_FLAG) == C::RUBY_FIXNUM_FLAG
    end

    def flonum?(obj)
      (C.to_value(obj) & C::RUBY_FLONUM_MASK) == C::RUBY_FLONUM_FLAG
    end

    def symbol?(obj)
      static_symbol?(obj) || dynamic_symbol?(obj)
    end

    def static_symbol?(obj)
      (C.to_value(obj) & 0xff) == C::RUBY_SYMBOL_FLAG
    end

    def dynamic_symbol?(obj)
      return false if C::SPECIAL_CONST_P(obj)
      C.RB_TYPE_P(obj, C::RUBY_T_SYMBOL)
    end

    def shape_too_complex?(obj)
      C.rb_shape_get_shape_id(obj) == C::OBJ_TOO_COMPLEX_SHAPE_ID
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def defer_compilation(jit, ctx, asm)
      # Make a stub to compile the current insn
      if ctx.chain_depth != 0
        raise "double defer!"
      end
      ctx.chain_depth += 1
      jit_direct_jump(jit.iseq, jit.pc, ctx, asm, comment: 'defer_compilation')
    end

    def jit_direct_jump(iseq, pc, ctx, asm, comment: 'jit_direct_jump')
      branch_stub = BranchStub.new(
        iseq:,
        shape: Default,
        target0: BranchTarget.new(ctx:, pc:),
      )
      branch_stub.target0.address = Assembler.new.then do |ocb_asm|
        @exit_compiler.compile_branch_stub(ctx, ocb_asm, branch_stub, true)
        @ocb.write(ocb_asm)
      end
      branch_stub.compile = compile_jit_direct_jump(branch_stub, comment:)
      branch_stub.compile.call(asm)
    end

    def compile_jit_direct_jump(branch_stub, comment:) # Proc escapes arguments in memory
      proc do |branch_asm|
        branch_asm.comment(comment)
        branch_asm.stub(branch_stub) do
          case branch_stub.shape
          in Default
            branch_asm.jmp(branch_stub.target0.address)
          in Next0
            # Just write the block without a jump
          end
        end
      end
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    def side_exit(jit, ctx)
      # We use the latest ctx.sp_offset to generate a side exit to tolerate sp_offset changes by jit_save_sp.
      # However, we want to simulate an old stack_size when we take a side exit. We do that by adjusting the
      # sp_offset because gen_outlined_exit uses ctx.sp_offset to move SP.
      ctx = ctx.with_stack_size(jit.stack_size_for_pc)

      jit.side_exit_for_pc[ctx.sp_offset] ||= Assembler.new.then do |asm|
        @exit_compiler.compile_side_exit(jit.pc, ctx, asm)
        @ocb.write(asm)
      end
    end

    def counted_exit(side_exit, name)
      asm = Assembler.new
      asm.incr_counter(name)
      asm.jmp(side_exit)
      @ocb.write(asm)
    end

    def def_iseq_ptr(cme_def)
      C.rb_iseq_check(cme_def.body.iseq.iseqptr)
    end

    def to_value(obj)
      GC_REFS << obj
      C.to_value(obj)
    end

    def full_cfunc_return
      @full_cfunc_return ||= Assembler.new.then do |asm|
        @exit_compiler.compile_full_cfunc_return(asm)
        @ocb.write(asm)
      end
    end

    def c_method_tracing_currently_enabled?
      C.rb_rjit_global_events & (C::RUBY_EVENT_C_CALL | C::RUBY_EVENT_C_RETURN) != 0
    end

    # Return a builtin function if a given iseq consists of only that builtin function
    def builtin_function(iseq)
      opt_invokebuiltin_delegate_leave = INSNS.values.find { |i| i.name == :opt_invokebuiltin_delegate_leave }
      leave = INSNS.values.find { |i| i.name == :leave }
      if iseq.body.iseq_size == opt_invokebuiltin_delegate_leave.len + leave.len &&
          C.rb_vm_insn_decode(iseq.body.iseq_encoded[0]) == opt_invokebuiltin_delegate_leave.bin &&
          C.rb_vm_insn_decode(iseq.body.iseq_encoded[opt_invokebuiltin_delegate_leave.len]) == leave.bin
        C.rb_builtin_function.new(iseq.body.iseq_encoded[1])
      end
    end

    def build_calling(ci:, block_handler:)
      CallingInfo.new(
        argc: C.vm_ci_argc(ci),
        flags: C.vm_ci_flag(ci),
        kwarg: C.vm_ci_kwarg(ci),
        ci_addr: ci.to_i,
        send_shift: 0,
        block_handler:,
      )
    end
  end
end
