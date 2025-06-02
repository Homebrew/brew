class RubyVM::RJIT::Block < Struct.new(
  :iseq,        # @param ``
  :pc,          # @param [Integer] Starting PC
  :ctx,         # @param [RubyVM::RJIT::Context] **Starting** Context (TODO: freeze?)
  :start_addr,  # @param [Integer] Starting address of this block's JIT code
  :entry_exit,  # @param [Integer] Address of entry exit (optional)
  :incoming,    # @param [Array<RubyVM::RJIT::BranchStub>] Incoming branches
  :invalidated, # @param [TrueClass,FalseClass] true if already invalidated
)
  def initialize(incoming: [], invalidated: false, **) = super
end
