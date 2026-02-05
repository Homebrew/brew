require 'bindata/base'
require 'bindata/dsl'

module BinData
  # A Section is a layer on top of a stream that transforms the underlying
  # data.  This allows BinData to process a stream that has multiple
  # encodings.  e.g.  Some data data is compressed or encrypted.
  #
  #   require 'bindata'
  #
  #   class XorTransform < BinData::IO::Transform
  #      def initialize(xor)
  #        super()
  #        @xor = xor
  #      end
  #
  #      def read(n)
  #        chain_read(n).bytes.map { |byte| (byte ^ @xor).chr }.join
  #      end
  #
  #      def write(data)
  #        chain_write(data.bytes.map { |byte| (byte ^ @xor).chr }.join)
  #      end
  #   end
  #
  #   obj = BinData::Section.new(transform: -> { XorTransform.new(0xff) },
  #                              type: [:string, read_length: 5])
  #
  #   obj.read("\x97\x9A\x93\x93\x90") #=> "hello"
  #
  #
  # == Parameters
  #
  # Parameters may be provided at initialisation to control the behaviour of
  # an object.  These params are:
  #
  # <tt>:transform</tt>:: A callable that returns a new BinData::IO::Transform.
  # <tt>:type</tt>::      The single type inside the buffer.  Use a struct if
  #                       multiple fields are required.
  class Section < BinData::Base
    extend DSLMixin

    dsl_parser    :section
    arg_processor :section

    mandatory_parameters :transform, :type

    def initialize_instance
      @type = get_parameter(:type).instantiate(nil, self)
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

    def respond_to_missing?(symbol, include_all = false) # :nodoc:
      @type.respond_to?(symbol, include_all) || super
    end

    def method_missing(symbol, *args, &block) # :nodoc:
      @type.__send__(symbol, *args, &block)
    end

    def do_read(io) # :nodoc:
      io.transform(eval_parameter(:transform)) do |transformed_io, _raw_io|
        @type.do_read(transformed_io)
      end
    end

    def do_write(io) # :nodoc:
      io.transform(eval_parameter(:transform)) do |transformed_io, _raw_io|
        @type.do_write(transformed_io)
      end
    end

    def do_num_bytes # :nodoc:
      to_binary_s.size
    end
  end

  class SectionArgProcessor < BaseArgProcessor
    include MultiFieldArgSeparator

    def sanitize_parameters!(obj_class, params)
      params.merge!(obj_class.dsl_params)
      params.sanitize_object_prototype(:type)
    end
  end
end
