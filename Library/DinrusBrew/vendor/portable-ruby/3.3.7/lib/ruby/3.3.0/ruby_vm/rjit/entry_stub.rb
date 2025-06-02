module RubyVM::RJIT
  class EntryStub < Struct.new(
    :start_addr, # @param [Integer] Stub source start address to be re-generated
    :end_addr,   # @param [Integer] Stub source end address to be re-generated
  )
  end
end
