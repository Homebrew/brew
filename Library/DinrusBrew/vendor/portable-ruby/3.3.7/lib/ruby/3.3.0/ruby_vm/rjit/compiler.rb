require 'ruby_vm/rjit/assembler'
require 'ruby_vm/rjit/block'
require 'ruby_vm/rjit/branch_stub'
require 'ruby_vm/rjit/code_block'
require 'ruby_vm/rjit/context'
require 'ruby_vm/rjit/entry_stub'
require 'ruby_vm/rjit/exit_compiler'
require 'ruby_vm/rjit/insn_compiler'
require 'ruby_vm/rjit/instruction'
require 'ruby_vm/rjit/invariants'
require 'ruby_vm/rjit/jit_state'
require 'ruby_vm/rjit/type'

module RubyVM::RJIT
  # Compilation status
  KeepCompiling = :KeepCompiling
  CantCompile = :CantCompile
  EndBlock = :EndBlock

  # Ruby constants
  Qtrue = Fiddle::Qtrue
  Qfalse = Fiddle::Qfalse
  Qnil = Fiddle::Qnil
  Qundef = Fiddle::Qundef

  # Callee-saved registers
  # TODO: support using r12/r13 here
  EC  = :r14
  CFP = :r15
  SP  = :rbx

  # Scratch registers: rax, rcx, rdx

  # Mark objects in this Array during GC
  GC_REFS = []

  # Maximum number of versions per block
  # 1 means always create generic versions
  MAX_VERSIONS = 4

  class Compiler
    attr_accessor :write_pos

    def self.decode_insn(encoded)
      INSNS.fetch(C.rb_vm_insn_decode(encoded))
    end

    def initialize
      mem_size = C.rjit_opts.exec_mem_size * 1024 * 1024
      mem_block = C.mmap(mem_size)
      @cb = CodeBlock.new(mem_block: mem_block, mem_size: mem_size / 2)
      @ocb = CodeBlock.new(mem_block: mem_block + mem_size / 2, mem_size: mem_size / 2, outlined: true)
      @exit_compiler = ExitCompiler.new
      @insn_compiler = InsnCompiler.new(@cb, @ocb, @exit_compiler)
      Invariants.initialize(@cb, @ocb, self, @exit_compiler)
    end

    # Compile an ISEQ from its entry point.
    # @param iseq `RubyVM::RJIT::CPointer::Struct_rb_iseq_t`
    # @param cfp `RubyVM::RJIT::CPointer::Struct_rb_control_frame_t`
    def compile(iseq, cfp)
      return unless supported_platform?
      pc = cfp.pc.to_i
      jit = JITState.new(iseq:, cfp:)
      asm = Assembler.new
      compile_prologue(asm, iseq, pc)
      compile_block(asm, jit:, pc:)
      iseq.body.jit_entry = @cb.write(asm)
    rescue Exception => e
      STDERR.puts "#{e.class}: #{e.message}"
      STDERR.puts e.backtrace
      exit 1
    end

    # Compile an entry.
    # @param entry [RubyVM::RJIT::EntryStub]
    def entry_stub_hit(entry_stub, cfp)
      # Compile a new entry guard as a next entry
      pc = cfp.pc.to_i
      next_entry = Assembler.new.then do |asm|
        compile_entry_chain_guard(asm, cfp.iseq, pc)
        @cb.write(asm)
      end

      # Try to find an existing compiled version of this block
      ctx = Context.new
      block = find_block(cfp.iseq, pc, ctx)
      if block
        # If an existing block is found, generate a jump to the block.
        asm = Assembler.new
        asm.jmp(block.start_addr)
        @cb.write(asm)
      else
        # If this block hasn't yet been compiled, generate blocks after the entry guard.
        asm = Assembler.new
        jit = JITState.new(iseq: cfp.iseq, cfp:)
        compile_block(asm, jit:, pc:, ctx:)
        @cb.write(asm)

        block = jit.block
      end

      # Regenerate the previous entry
      @cb.with_write_addr(entry_stub.start_addr) do
        # The last instruction of compile_entry_chain_guard is jne
        asm = Assembler.new
        asm.jne(next_entry)
        @cb.write(asm)
      end

      return block.start_addr
    rescue Exception => e
      STDERR.puts e.full_message
      exit 1
    end

    # Compile a branch stub.
    # @param branch_stub [RubyVM::RJIT::BranchStub]
    # @param cfp `RubyVM::RJIT::CPointer::Struct_rb_control_frame_t`
    # @param target0_p [TrueClass,FalseClass]
    # @return [Integer] The starting address of the compiled branch stub
    def branch_stub_hit(branch_stub, cfp, target0_p)
      # Update cfp->pc for `jit.at_current_insn?`
      target = target0_p ? branch_stub.target0 : branch_stub.target1
      cfp.pc = target.pc

      # Reuse an existing block if it already exists
      block = find_block(branch_stub.iseq, target.pc, target.ctx)

      # If the branch stub's jump is the last code, allow overwriting part of
      # the old branch code with the new block code.
      fallthrough = block.nil? && @cb.write_addr == branch_stub.end_addr
      if fallthrough
        # If the branch stub's jump is the last code, allow overwriting part of
        # the old branch code with the new block code.
        @cb.set_write_addr(branch_stub.start_addr)
        branch_stub.shape = target0_p ? Next0 : Next1
        Assembler.new.tap do |branch_asm|
          branch_stub.compile.call(branch_asm)
          @cb.write(branch_asm)
        end
      end

      # Reuse or generate a block
      if block
        target.address = block.start_addr
      else
        jit = JITState.new(iseq: branch_stub.iseq, cfp:)
        target.address = Assembler.new.then do |asm|
          compile_block(asm, jit:, pc: target.pc, ctx: target.ctx.dup)
          @cb.write(asm)
        end
        block = jit.block
      end
      block.incoming << branch_stub # prepare for invalidate_block

      # Re-generate the branch code for non-fallthrough cases
      unless fallthrough
        @cb.with_write_addr(branch_stub.start_addr) do
          branch_asm = Assembler.new
          branch_stub.compile.call(branch_asm)
          @cb.write(branch_asm)
        end
      end

      return target.address
    rescue Exception => e
      STDERR.puts e.full_message
      exit 1
    end

    # @param iseq `RubyVM::RJIT::CPointer::Struct_rb_iseq_t`
    # @param pc [Integer]
    def invalidate_blocks(iseq, pc)
      list_blocks(iseq, pc).each do |block|
        invalidate_block(block)
      end

      # If they were the ISEQ's first blocks, re-compile RJIT entry as well
      if iseq.body.iseq_encoded.to_i == pc
        iseq.body.jit_entry = 0
        iseq.body.jit_entry_calls = 0
      end
    end

    def invalidate_block(block)
      iseq = block.iseq
      # Avoid touching GCed ISEQs. We assume it won't be re-entered.
      return unless C.imemo_type_p(iseq, C.imemo_iseq)

      # Remove this block from the version array
      remove_block(iseq, block)

      # Invalidate the block with entry exit
      unless block.invalidated
        @cb.with_write_addr(block.start_addr) do
          asm = Assembler.new
          asm.comment('invalidate_block')
          asm.jmp(block.entry_exit)
          @cb.write(asm)
        end
        block.invalidated = true
      end

      # Re-stub incoming branches
      block.incoming.each do |branch_stub|
        target = [branch_stub.target0, branch_stub.target1].compact.find do |target|
          target.pc == block.pc && target.ctx == block.ctx
        end
        next if target.nil?
        # TODO: Could target.address be a stub address? Is invalidation not needed in that case?

        # If the target being re-generated is currently a fallthrough block,
        # the fallthrough code must be rewritten with a jump to the stub.
        if target.address == branch_stub.end_addr
          branch_stub.shape = Default
        end

        target.address = Assembler.new.then do |ocb_asm|
          @exit_compiler.compile_branch_stub(block.ctx, ocb_asm, branch_stub, target == branch_stub.target0)
          @ocb.write(ocb_asm)
        end
        @cb.with_write_addr(branch_stub.start_addr) do
          branch_asm = Assembler.new
          branch_stub.compile.call(branch_asm)
          @cb.write(branch_asm)
        end
      end
    end

    private

    # Callee-saved: rbx, rsp, rbp, r12, r13, r14, r15
    # Caller-saved: rax, rdi, rsi, rdx, rcx, r8, r9, r10, r11
    #
    # @param asm [RubyVM::RJIT::Assembler]
    def compile_prologue(asm, iseq, pc)
      asm.comment('RJIT entry point')

      # Save callee-saved registers used by JITed code
      asm.push(CFP)
      asm.push(EC)
      asm.push(SP)

      # Move arguments EC and CFP to dedicated registers
      asm.mov(EC, :rdi)
      asm.mov(CFP, :rsi)

      # Load sp to a dedicated register
      asm.mov(SP, [CFP, C.rb_control_frame_t.offsetof(:sp)]) # rbx = cfp->sp

      # Setup cfp->jit_return
      asm.mov(:rax, leave_exit)
      asm.mov([CFP, C.rb_control_frame_t.offsetof(:jit_return)], :rax)

      # We're compiling iseqs that we *expect* to start at `insn_idx`. But in
      # the case of optional parameters, the interpreter can set the pc to a
      # different location depending on the optional parameters.  If an iseq
      # has optional parameters, we'll add a runtime check that the PC we've
      # compiled for is the same PC that the interpreter wants us to run with.
      # If they don't match, then we'll take a side exit.
      if iseq.body.param.flags.has_opt
        compile_entry_chain_guard(asm, iseq, pc)
      end
    end

    def compile_entry_chain_guard(asm, iseq, pc)
      entry_stub = EntryStub.new
      stub_addr = Assembler.new.then do |ocb_asm|
        @exit_compiler.compile_entry_stub(ocb_asm, entry_stub)
        @ocb.write(ocb_asm)
      end

      asm.comment('guard expected PC')
      asm.mov(:rax, pc)
      asm.cmp([CFP, C.rb_control_frame_t.offsetof(:pc)], :rax)

      asm.stub(entry_stub) do
        asm.jne(stub_addr)
      end
    end

    # @param asm [RubyVM::RJIT::Assembler]
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    def compile_block(asm, jit:, pc:, ctx: Context.new)
      # Mark the block start address and prepare an exit code storage
      ctx = limit_block_versions(jit.iseq, pc, ctx)
      block = Block.new(iseq: jit.iseq, pc:, ctx: ctx.dup)
      jit.block = block
      asm.block(block)

      iseq = jit.iseq
      asm.comment("Block: #{iseq.body.location.label}@#{C.rb_iseq_path(iseq)}:#{iseq_lineno(iseq, pc)}")

      # Compile each insn
      index = (pc - iseq.body.iseq_encoded.to_i) / C.VALUE.size
      while index < iseq.body.iseq_size
        # Set the current instruction
        insn = self.class.decode_insn(iseq.body.iseq_encoded[index])
        jit.pc = (iseq.body.iseq_encoded + index).to_i
        jit.stack_size_for_pc = ctx.stack_size
        jit.side_exit_for_pc.clear

        # If previous instruction requested to record the boundary
        if jit.record_boundary_patch_point
          # Generate an exit to this instruction and record it
          exit_pos = Assembler.new.then do |ocb_asm|
            @exit_compiler.compile_side_exit(jit.pc, ctx, ocb_asm)
            @ocb.write(ocb_asm)
          end
          Invariants.record_global_inval_patch(asm, exit_pos)
          jit.record_boundary_patch_point = false
        end

        # In debug mode, verify our existing assumption
        if C.rjit_opts.verify_ctx && jit.at_current_insn?
          verify_ctx(jit, ctx)
        end

        case status = @insn_compiler.compile(jit, ctx, asm, insn)
        when KeepCompiling
          # For now, reset the chain depth after each instruction as only the
          # first instruction in the block can concern itself with the depth.
          ctx.chain_depth = 0

          index += insn.len
        when EndBlock
          # TODO: pad nops if entry exit exists (not needed for x86_64?)
          break
        when CantCompile
          # Rewind stack_size using ctx.with_stack_size to allow stack_size changes
          # before you return CantCompile.
          @exit_compiler.compile_side_exit(jit.pc, ctx.with_stack_size(jit.stack_size_for_pc), asm)

          # If this is the first instruction, this block never needs to be invalidated.
          if block.pc == iseq.body.iseq_encoded.to_i + index * C.VALUE.size
            block.invalidated = true
          end

          break
        else
          raise "compiling #{insn.name} returned unexpected status: #{status.inspect}"
        end
      end

      incr_counter(:compiled_block_count)
      add_block(iseq, block)
    end

    def leave_exit
      @leave_exit ||= Assembler.new.then do |asm|
        @exit_compiler.compile_leave_exit(asm)
        @ocb.write(asm)
      end
    end

    def incr_counter(name)
      if C.rjit_opts.stats
        C.rb_rjit_counters[name][0] += 1
      end
    end

    # Produce a generic context when the block version limit is hit for the block
    def limit_block_versions(iseq, pc, ctx)
      # Guard chains implement limits separately, do nothing
      if ctx.chain_depth > 0
        return ctx.dup
      end

      # If this block version we're about to add will hit the version limit
      if list_blocks(iseq, pc).size + 1 >= MAX_VERSIONS
        # Produce a generic context that stores no type information,
        # but still respects the stack_size and sp_offset constraints.
        # This new context will then match all future requests.
        generic_ctx = Context.new
        generic_ctx.stack_size = ctx.stack_size
        generic_ctx.sp_offset = ctx.sp_offset

        if ctx.diff(generic_ctx) == TypeDiff::Incompatible
          raise 'should substitute a compatible context'
        end

        return generic_ctx
      end

      return ctx.dup
    end

    def list_blocks(iseq, pc)
      rjit_blocks(iseq)[pc]
    end

    # @param [Integer] pc
    # @param [RubyVM::RJIT::Context] ctx
    # @return [RubyVM::RJIT::Block,NilClass]
    def find_block(iseq, pc, ctx)
      versions = rjit_blocks(iseq)[pc]

      best_version = nil
      best_diff = Float::INFINITY

      versions.each do |block|
        # Note that we always prefer the first matching
        # version found because of inline-cache chains
        case ctx.diff(block.ctx)
        in TypeDiff::Compatible[diff] if diff < best_diff
          best_version = block
          best_diff = diff
        else
        end
      end

      return best_version
    end

    # @param [RubyVM::RJIT::Block] block
    def add_block(iseq, block)
      rjit_blocks(iseq)[block.pc] << block
    end

    # @param [RubyVM::RJIT::Block] block
    def remove_block(iseq, block)
      rjit_blocks(iseq)[block.pc].delete(block)
    end

    def rjit_blocks(iseq)
      # Guard against ISEQ GC at random moments

      unless C.imemo_type_p(iseq, C.imemo_iseq)
        return Hash.new { |h, k| h[k] = [] }
      end

      unless iseq.body.rjit_blocks
        iseq.body.rjit_blocks = Hash.new { |blocks, pc| blocks[pc] = [] }
        # For some reason, rb_rjit_iseq_mark didn't protect this Hash
        # from being freed. So we rely on GC_REFS to keep the Hash.
        GC_REFS << iseq.body.rjit_blocks
      end
      iseq.body.rjit_blocks
    end

    def iseq_lineno(iseq, pc)
      C.rb_iseq_line_no(iseq, (pc - iseq.body.iseq_encoded.to_i) / C.VALUE.size)
    rescue RangeError # bignum too big to convert into `unsigned long long' (RangeError)
      -1
    end

    # Verify the ctx's types and mappings against the compile-time stack, self, and locals.
    # @param jit [RubyVM::RJIT::JITState]
    # @param ctx [RubyVM::RJIT::Context]
    def verify_ctx(jit, ctx)
      # Only able to check types when at current insn
      assert(jit.at_current_insn?)

      self_val = jit.peek_at_self
      self_val_type = Type.from(self_val)

      # Verify self operand type
      assert_compatible(self_val_type, ctx.get_opnd_type(SelfOpnd))

      # Verify stack operand types
      [ctx.stack_size, MAX_TEMP_TYPES].min.times do |i|
        learned_mapping, learned_type = ctx.get_opnd_mapping(StackOpnd[i])
        stack_val = jit.peek_at_stack(i)
        val_type = Type.from(stack_val)

        case learned_mapping
        in MapToSelf
          if C.to_value(self_val) != C.to_value(stack_val)
            raise "verify_ctx: stack value was mapped to self, but values did not match:\n"\
              "stack: #{stack_val.inspect}, self: #{self_val.inspect}"
          end
        in MapToLocal[local_idx]
          local_val = jit.peek_at_local(local_idx)
          if C.to_value(local_val) != C.to_value(stack_val)
            raise "verify_ctx: stack value was mapped to local, but values did not match:\n"\
              "stack: #{stack_val.inspect}, local: #{local_val.inspect}"
          end
        in MapToStack
          # noop
        end

        # If the actual type differs from the learned type
        assert_compatible(val_type, learned_type)
      end

      # Verify local variable types
      local_table_size = jit.iseq.body.local_table_size
      [local_table_size, MAX_TEMP_TYPES].min.times do |i|
        learned_type = ctx.get_local_type(i)
        local_val = jit.peek_at_local(i)
        local_type = Type.from(local_val)

        assert_compatible(local_type, learned_type)
      end
    end

    def assert_compatible(actual_type, ctx_type)
      if actual_type.diff(ctx_type) == TypeDiff::Incompatible
        raise "verify_ctx: ctx type (#{ctx_type.type.inspect}) is incompatible with actual type (#{actual_type.type.inspect})"
      end
    end

    def assert(cond)
      unless cond
        raise "'#{cond.inspect}' was not true"
      end
    end

    def supported_platform?
      return @supported_platform if defined?(@supported_platform)
      @supported_platform = RUBY_PLATFORM.match?(/x86_64/).tap do |supported|
        warn "warning: RJIT does not support #{RUBY_PLATFORM} yet" unless supported
      end
    end
  end
end
