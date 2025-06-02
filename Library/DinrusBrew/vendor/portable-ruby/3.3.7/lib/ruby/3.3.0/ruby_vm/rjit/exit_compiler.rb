module RubyVM::RJIT
  class ExitCompiler
    def initialize = freeze

    # Used for invalidating a block on entry.
    # @param pc [Integer]
    # @param asm [RubyVM::RJIT::Assembler]
    def compile_entry_exit(pc, ctx, asm, cause:)
      # Fix pc/sp offsets for the interpreter
      save_pc_and_sp(pc, ctx, asm, reset_sp_offset: false)

      # Increment per-insn exit counter
      count_insn_exit(pc, asm)

      # Restore callee-saved registers
      asm.comment("#{cause}: entry exit")
      asm.pop(SP)
      asm.pop(EC)
      asm.pop(CFP)

      asm.mov(C_RET, Qundef)
      asm.ret
    end

    # Set to cfp->jit_return by default for leave insn
    # @param asm [RubyVM::RJIT::Assembler]
    def compile_leave_exit(asm)
      asm.comment('default cfp->jit_return')

      # Restore callee-saved registers
      asm.pop(SP)
      asm.pop(EC)
      asm.pop(CFP)

      # :rax is written by #leave
      asm.ret
    end

    # Fire cfunc events on invalidation by TracePoint
    # @param asm [RubyVM::RJIT::Assembler]
    def compile_full_cfunc_return(asm)
      # This chunk of code expects REG_EC to be filled properly and
      # RAX to contain the return value of the C method.

      asm.comment('full cfunc return')
      asm.mov(C_ARGS[0], EC)
      asm.mov(C_ARGS[1], :rax)
      asm.call(C.rjit_full_cfunc_return)

      # TODO: count the exit

      # Restore callee-saved registers
      asm.pop(SP)
      asm.pop(EC)
      asm.pop(CFP)

      asm.mov(C_RET, Qundef)
      asm.ret
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def compile_side_exit(pc, ctx, asm)
      # Fix pc/sp offsets for the interpreter
      save_pc_and_sp(pc, ctx.dup, asm) # dup to avoid sp_offset update

      # Increment per-insn exit counter
      count_insn_exit(pc, asm)

      # Restore callee-saved registers
      asm.comment("exit to interpreter on #{pc_to_insn(pc).name}")
      asm.pop(SP)
      asm.pop(EC)
      asm.pop(CFP)

      asm.mov(C_RET, Qundef)
      asm.ret
    end

    # @param asm [RubyVM::RJIT::Assembler]
    # @param entry_stub [RubyVM::RJIT::EntryStub]
    def compile_entry_stub(asm, entry_stub)
      # Call rb_rjit_entry_stub_hit
      asm.comment('entry stub hit')
      asm.mov(C_ARGS[0], to_value(entry_stub))
      asm.call(C.rb_rjit_entry_stub_hit)

      # Jump to the address returned by rb_rjit_entry_stub_hit
      asm.jmp(:rax)
    end

    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    # @param branch_stub [RubyVM::RJIT::BranchStub]
    # @param target0_p [TrueClass,FalseClass]
    def compile_branch_stub(ctx, asm, branch_stub, target0_p)
      # Call rb_rjit_branch_stub_hit
      iseq = branch_stub.iseq
      if C.rjit_opts.dump_disasm && C.imemo_type_p(iseq, C.imemo_iseq) # Guard against ISEQ GC at random moments
        asm.comment("branch stub hit: #{iseq.body.location.label}@#{C.rb_iseq_path(iseq)}:#{iseq_lineno(iseq, target0_p ? branch_stub.target0.pc : branch_stub.target1.pc)}")
      end
      asm.mov(:rdi, to_value(branch_stub))
      asm.mov(:esi, ctx.sp_offset)
      asm.mov(:edx, target0_p ? 1 : 0)
      asm.call(C.rb_rjit_branch_stub_hit)

      # Jump to the address returned by rb_rjit_branch_stub_hit
      asm.jmp(:rax)
    end

    private

    def pc_to_insn(pc)
      Compiler.decode_insn(C.VALUE.new(pc).*)
    end

    # @param pc [Integer]
    # @param asm [RubyVM::RJIT::Assembler]
    def count_insn_exit(pc, asm)
      if C.rjit_opts.stats
        insn = Compiler.decode_insn(C.VALUE.new(pc).*)
        asm.comment("increment insn exit: #{insn.name}")
        asm.mov(:rax, (C.rjit_insn_exits + insn.bin).to_i)
        asm.add([:rax], 1) # TODO: lock
      end
      if C.rjit_opts.trace_exits
        asm.comment('rjit_record_exit_stack')
        asm.mov(C_ARGS[0], pc)
        asm.call(C.rjit_record_exit_stack)
      end
    end

    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    # @param asm [RubyVM::RJIT::Assembler]
    def save_pc_and_sp(pc, ctx, asm, reset_sp_offset: true)
      # Update pc (TODO: manage PC offset?)
      asm.comment("save PC#{' and SP' if ctx.sp_offset != 0} to CFP")
      asm.mov(:rax, pc) # rax = jit.pc
      asm.mov([CFP, C.rb_control_frame_t.offsetof(:pc)], :rax) # cfp->pc = rax

      # Update sp
      if ctx.sp_offset != 0
        asm.add(SP, C.VALUE.size * ctx.sp_offset) # sp += stack_size
        asm.mov([CFP, C.rb_control_frame_t.offsetof(:sp)], SP) # cfp->sp = sp
        if reset_sp_offset
          ctx.sp_offset = 0
        end
      end
    end

    def to_value(obj)
      GC_REFS << obj
      C.to_value(obj)
    end

    def iseq_lineno(iseq, pc)
      C.rb_iseq_line_no(iseq, (pc - iseq.body.iseq_encoded.to_i) / C.VALUE.size)
    rescue RangeError # bignum too big to convert into `unsigned long long' (RangeError)
      -1
    end
  end
end
