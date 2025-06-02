module RubyVM::RJIT
  # Branch shapes
  Next0   = :Next0   # target0 is a fallthrough
  Next1   = :Next1   # target1 is a fallthrough
  Default = :Default # neither targets is a fallthrough

  class BranchStub < Struct.new(
    :iseq,       # @param [RubyVM::RJIT::CPointer::Struct_rb_iseq_struct] Branch target ISEQ
    :shape,      # @param [Symbol] Next0, Next1, or Default
    :target0,    # @param [RubyVM::RJIT::BranchTarget] First branch target
    :target1,    # @param [RubyVM::RJIT::BranchTarget,NilClass] Second branch target (optional)
    :compile,    # @param [Proc] A callback to (re-)generate this branch stub
    :start_addr, # @param [Integer] Stub source start address to be re-generated
    :end_addr,   # @param [Integer] Stub source end address to be re-generated
  )
  end

  class BranchTarget < Struct.new(
    :pc,
    :ctx,
    :address,
  )
  end
end
