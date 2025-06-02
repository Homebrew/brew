# frozen_string_literal: true
module Fiddle
  class Closure

    # the C type of the return of the FFI closure
    attr_reader :ctype

    # arguments of the FFI closure
    attr_reader :args

    # Extends Fiddle::Closure to allow for building the closure in a block
    class BlockCaller < Fiddle::Closure

      # == Description
      #
      # Construct a new BlockCaller object.
      #
      # * +ctype+ is the C type to be returned
      # * +args+ are passed the callback
      # * +abi+ is the abi of the closure
      #
      # If there is an error in preparing the +ffi_cif+ or +ffi_prep_closure+,
      # then a RuntimeError will be raised.
      #
      # == Example
      #
      #   include Fiddle
      #
      #   cb = Closure::BlockCaller.new(TYPE_INT, [TYPE_INT]) do |one|
      #     one
      #   end
      #
      #   func = Function.new(cb, [TYPE_INT], TYPE_INT)
      #
      def initialize ctype, args, abi = Fiddle::Function::DEFAULT, &block
        super(ctype, args, abi)
        @block = block
      end

      # Calls the constructed BlockCaller, with +args+
      #
      # For an example see Fiddle::Closure::BlockCaller.new
      #
      def call *args
        @block.call(*args)
      end
    end
  end
end
