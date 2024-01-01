require "bindata/base_primitive"

module BinData
  # Uint8Array is a specialised type of array that only contains
  # bytes (Uint8).  It is a faster and more memory efficient version
  # of `BinData::Array.new(:type => :uint8)`.
  #
  #   require 'bindata'
  #
  #   obj = BinData::Uint8Array.new(initial_length: 5)
  #   obj.read("abcdefg") #=> [97, 98, 99, 100, 101]
  #   obj[2] #=> 99
  #   obj.collect { |x| x.chr }.join #=> "abcde"
  #
  # == Parameters
  #
  # Parameters may be provided at initialisation to control the behaviour of
  # an object.  These params are:
  #
  # <tt>:initial_length</tt>:: The initial length of the array.
  # <tt>:read_until</tt>::     May only have a value of `:eof`.  This parameter
  #                            instructs the array to read as much data from
  #                            the stream as possible.
  class Uint8Array < BinData::BasePrimitive
    optional_parameters :initial_length, :read_until
    mutually_exclusive_parameters :initial_length, :read_until
    arg_processor :uint8_array

    #---------------
    private

    def value_to_binary_string(val)
      val.pack("C*")
    end

    def read_and_return_value(io)
      if has_parameter?(:initial_length)
        data = io.readbytes(eval_parameter(:initial_length))
      else
        data = io.read_all_bytes
      end

      data.unpack("C*")
    end

    def sensible_default
      []
    end
  end

  class Uint8ArrayArgProcessor < BaseArgProcessor
    def sanitize_parameters!(obj_class, params) #:nodoc:
      # ensure one of :initial_length and :read_until exists
      unless params.has_at_least_one_of?(:initial_length, :read_until)
        params[:initial_length] = 0
      end

      msg = "Parameter :read_until must have a value of :eof"
      params.sanitize(:read_until) { |val| raise ArgumentError, msg unless val == :eof }
    end
  end
end
