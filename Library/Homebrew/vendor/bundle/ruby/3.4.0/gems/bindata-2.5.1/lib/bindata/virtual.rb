require 'bindata/base'

module BinData
  # A virtual field is one that is neither read, written nor occupies space in
  # the data stream.  It is used to make assertions or as a convenient label
  # for determining offsets or storing values.
  #
  #   require 'bindata'
  #
  #   class A < BinData::Record
  #     string  :a, read_length: 5
  #     string  :b, read_length: 5
  #     virtual :c, assert: -> { a == b }
  #   end
  #
  #   obj = A.read("abcdeabcde")
  #   obj.a #=> "abcde"
  #   obj.c.rel_offset #=> 10
  #
  #   obj = A.read("abcdeABCDE") #=> BinData::ValidityError: assertion failed for obj.c
  #
  # == Parameters
  #
  # Parameters may be provided at initialisation to control the behaviour of
  # an object.  These params include those for BinData::Base as well as:
  #
  # [<tt>:assert</tt>]    Raise an error when reading or assigning if the value
  #                       of this evaluated parameter is false.
  # [<tt>:value</tt>]     The virtual object will always have this value.
  #
  class Virtual < BinData::BasePrimitive
    def do_read(io); end

    def do_write(io); end

    def do_num_bytes
      0.0
    end

    def sensible_default
      nil
    end
  end
end
