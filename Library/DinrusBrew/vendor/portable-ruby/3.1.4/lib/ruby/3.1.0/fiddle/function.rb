# frozen_string_literal: true
module Fiddle
  class Function
    # The ABI of the Function.
    attr_reader :abi

    # The address of this function
    attr_reader :ptr

    # The name of this function
    attr_reader :name

    # Whether GVL is needed to call this function
    def need_gvl?
      @need_gvl
    end

    # The integer memory location of this function
    def to_i
      ptr.to_i
    end

    # Turn this function in to a proc
    def to_proc
      this = self
      lambda { |*args| this.call(*args) }
    end
  end
end
