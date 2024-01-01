require 'bindata/base'
require 'bindata/dsl'

module BinData
  # A Buffer is conceptually a substream within a data stream.  It has a
  # defined size and it will always read or write the exact number of bytes to
  # fill the buffer.  Short reads will skip over unused bytes and short writes
  # will pad the substream with "\0" bytes.
  #
  #   require 'bindata'
  #
  #   obj = BinData::Buffer.new(length: 5, type: [:string, {value: "abc"}])
  #   obj.to_binary_s #=> "abc\000\000"
  #
  #
  #   class MyBuffer < BinData::Buffer
  #     default_parameter length: 8
  #
  #     endian :little
  #
  #     uint16 :num1
  #     uint16 :num2
  #     # padding occurs here
  #   end
  #
  #   obj = MyBuffer.read("\001\000\002\000\000\000\000\000")
  #   obj.num1 #=> 1
  #   obj.num1 #=> 2
  #   obj.raw_num_bytes #=> 4
  #   obj.num_bytes #=> 8
  #
  #
  #   class StringTable < BinData::Record
  #     endian :little
  #
  #     uint16 :table_size_in_bytes
  #     buffer :strings, length: :table_size_in_bytes do
  #       array read_until: :eof do
  #         uint8 :len
  #         string :str, length: :len
  #       end
  #     end
  #   end
  #     
  #
  # == Parameters
  #
  # Parameters may be provided at initialisation to control the behaviour of
  # an object.  These params are:
  #
  # <tt>:length</tt>::   The number of bytes in the buffer.
  # <tt>:type</tt>::     The single type inside the buffer.  Use a struct if
  #                      multiple fields are required.
  class Buffer < BinData::Base
    extend DSLMixin

    dsl_parser    :buffer
    arg_processor :buffer

    mandatory_parameters :length, :type

    def initialize_instance
      @type = get_parameter(:type).instantiate(nil, self)
    end

    # The number of bytes used, ignoring the padding imposed by the buffer.
    def raw_num_bytes
      @type.num_bytes
    end

    def clear?
      @type.clear?
    end

    def assign(val)
      @type.assign(val)
    end

    def snapshot
      @type.snapshot
    end

    def respond_to?(symbol, include_private = false) #:nodoc:
      @type.respond_to?(symbol, include_private) || super
    end

    def method_missing(symbol, *args, &block) #:nodoc:
      @type.__send__(symbol, *args, &block)
    end

    def do_read(io) #:nodoc:
      io.with_buffer(eval_parameter(:length)) do
        @type.do_read(io)
      end
    end

    def do_write(io) #:nodoc:
      io.with_buffer(eval_parameter(:length)) do
        @type.do_write(io)
      end
    end

    def do_num_bytes #:nodoc:
      eval_parameter(:length)
    end
  end

  class BufferArgProcessor < BaseArgProcessor
    include MultiFieldArgSeparator

    def sanitize_parameters!(obj_class, params)
      params.merge!(obj_class.dsl_params)
      params.must_be_integer(:length)
      params.sanitize_object_prototype(:type)
    end
  end
end
