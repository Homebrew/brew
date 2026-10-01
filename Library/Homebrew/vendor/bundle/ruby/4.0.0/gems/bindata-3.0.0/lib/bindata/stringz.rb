require 'bindata/base_primitive'

module BinData
  # A BinData::Stringz object is a container for a zero ("\0") terminated
  # string.
  #
  # For convenience, the zero terminator is not necessary when setting the
  # value.  Likewise, the returned value will not be zero terminated.
  #
  #   require 'bindata'
  #
  #   data = "abcd\x00efgh"
  #
  #   obj = BinData::Stringz.new
  #   obj.read(data)
  #   obj.snapshot #=> "abcd"
  #   obj.num_bytes #=> 5
  #   obj.to_binary_s #=> "abcd\000"
  #
  # == Parameters
  #
  # Stringz objects accept all the params that BinData::BasePrimitive
  # does, as well as the following:
  #
  # <tt>:max_length</tt>:: The maximum length of the string including the zero
  #                        byte.
  class Stringz < BinData::BasePrimitive
    optional_parameters :max_length

    def assign(val)
      super(binary_string(val))
    end

    def snapshot
      # override to always remove trailing zero bytes
      result = super
      trim_and_zero_terminate(result).chomp("\0")
    end

    #---------------
    private

    def value_to_binary_string(val)
      trim_and_zero_terminate(val)
    end

    def read_and_return_value(io)
      max_length = eval_parameter(:max_length)
      str = binary_string("")
      i = 0
      ch = nil

      # read until zero byte or we have read in the max number of bytes
      while ch != "\0" && i != max_length
        ch = io.readbytes(1)
        str << ch
        i += 1
      end

      trim_and_zero_terminate(str)
    end

    def sensible_default
      ""
    end

    def trim_and_zero_terminate(str)
      max_length = eval_parameter(:max_length)
      if max_length && max_length < 1
        msg = "max_length must be >= 1 in #{debug_name} (got #{max_length})"
        raise ArgumentError, msg
      end

      result = binary_string(str)
      truncate_after_first_zero_byte!(result)
      trim_to!(result, max_length)
      append_zero_byte_if_needed!(result)
      result
    end

    def truncate_after_first_zero_byte!(str)
      str.sub!(/([^\0]*\0).*/, '\1')
    end

    def trim_to!(str, max_length = nil)
      if max_length
        str.slice!(max_length..-1)
        str[-1, 1] = "\0" if str.length == max_length
      end
    end

    def append_zero_byte_if_needed!(str)
      if str.empty? || str[-1, 1] != "\0"
        str << "\0"
      end
    end
  end
end
