require 'set'

module RubyVM::RJIT
  class Invariants
    class << self
      # Called by RubyVM::RJIT::Compiler to lazily initialize this
      # @param cb [CodeBlock]
      # @param ocb [CodeBlock]
      # @param compiler [RubyVM::RJIT::Compiler]
      # @param exit_compiler [RubyVM::RJIT::ExitCompiler]
      def initialize(cb, ocb, compiler, exit_compiler)
        @cb = cb
        @ocb = ocb
        @compiler = compiler
        @exit_compiler = exit_compiler
        @bop_blocks = Set.new # TODO: actually invalidate this
        @cme_blocks = Hash.new { |h, k| h[k] = Set.new }
        @const_blocks = Hash.new { |h, k| h[k] = Set.new }
        @patches = {}

        # freeze # workaround a binding.irb issue. TODO: resurrect this
      end

      # @param jit [RubyVM::RJIT::JITState]
      # @param klass [Integer]
      # @param op [Integer]
      def assume_bop_not_redefined(jit, klass, op)
        return false unless C.BASIC_OP_UNREDEFINED_P(klass, op)

        ensure_block_entry_exit(jit, cause: 'assume_bop_not_redefined')
        @bop_blocks << jit.block
        true
      end

      # @param jit [RubyVM::RJIT::JITState]
      def assume_method_lookup_stable(jit, cme)
        ensure_block_entry_exit(jit, cause: 'assume_method_lookup_stable')
        @cme_blocks[cme.to_i] << jit.block
      end

      # @param jit [RubyVM::RJIT::JITState]
      def assume_method_basic_definition(jit, klass, mid)
        if C.rb_method_basic_definition_p(klass, mid)
          cme = C.rb_callable_method_entry(klass, mid)
          assume_method_lookup_stable(jit, cme)
          true
        else
          false
        end
      end

      def assume_stable_constant_names(jit, idlist)
        (0..).each do |i|
          break if (id = idlist[i]) == 0
          @const_blocks[id] << jit.block
        end
      end

      # @param asm [RubyVM::RJIT::Assembler]
      def record_global_inval_patch(asm, target)
        asm.pos_marker do |address|
          if @patches.key?(address)
            raise 'multiple patches in the same address'
          end
          @patches[address] = target
        end
      end

      def on_cme_invalidate(cme)
        @cme_blocks.fetch(cme.to_i, []).each do |block|
          @cb.with_write_addr(block.start_addr) do
            asm = Assembler.new
            asm.comment('on_cme_invalidate')
            asm.jmp(block.entry_exit)
            @cb.write(asm)
          end
          # TODO: re-generate branches that refer to this block
        end
        @cme_blocks.delete(cme.to_i)
      end

      def on_constant_ic_update(iseq, ic, insn_idx)
        # TODO: check multi ractor as well
        if ic.entry.ic_cref
          # No need to recompile the slowpath
          return
        end

        pc = iseq.body.iseq_encoded + insn_idx
        insn_name = Compiler.decode_insn(pc.*).name
        if insn_name != :opt_getconstant_path && insn_name != :trace_opt_getconstant_path
          raise 'insn_idx was not at opt_getconstant_path'
        end
        if ic.to_i != pc[1]
          raise 'insn_idx + 1 was not at the updated IC'
        end
        @compiler.invalidate_blocks(iseq, pc.to_i)
      end

      def on_constant_state_changed(id)
        @const_blocks.fetch(id, []).each do |block|
          @compiler.invalidate_block(block)
        end
      end

      def on_tracing_invalidate_all
        invalidate_all
      end

      def on_update_references
        # Give up. In order to support GC.compact, you'd have to update ISEQ
        # addresses in BranchStub, etc. Ideally, we'd need to update moved
        # pointers in JITed code here, but we just invalidate all for now.
        invalidate_all
      end

      # @param jit [RubyVM::RJIT::JITState]
      # @param block [RubyVM::RJIT::Block]
      def ensure_block_entry_exit(jit, cause:)
        block = jit.block
        if block.entry_exit.nil?
          block.entry_exit = Assembler.new.then do |asm|
            @exit_compiler.compile_entry_exit(block.pc, block.ctx, asm, cause:)
            @ocb.write(asm)
          end
        end
      end

      private

      def invalidate_all
        # On-Stack Replacement
        @patches.each do |address, target|
          # TODO: assert patches don't overlap each other
          @cb.with_write_addr(address) do
            asm = Assembler.new
            asm.comment('on_tracing_invalidate_all')
            asm.jmp(target)
            @cb.write(asm)
          end
        end
        @patches.clear

        C.rjit_for_each_iseq do |iseq|
          # Avoid entering past code
          iseq.body.jit_entry = 0
          # Avoid reusing past code
          iseq.body.rjit_blocks.clear if iseq.body.rjit_blocks
          # Compile this again if not converted to trace_* insns
          iseq.body.jit_entry_calls = 0
        end
      end
    end
  end
end
