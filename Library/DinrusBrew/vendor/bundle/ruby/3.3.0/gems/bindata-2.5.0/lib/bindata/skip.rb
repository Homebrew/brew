require 'bindata/base_primitive'
require 'bindata/dsl'

module BinData
  # Skip will skip over bytes from the input stream.  If the stream is not
  # seekable, then the bytes are consumed and discarded.
  #
  # When writing, skip will write the appropriate number of zero bytes.
  #
  #   require 'bindata'
  #
  #   class A < BinData::Record
  #     skip length: 5
  #     string :a, read_length: 5
  #   end
  #
  #   obj = A.read("abcdefghij")
  #   obj.a #=> "fghij"
  #
  #
  #   class B < BinData::Record
  #     skip do
  #       string read_length: 2, assert: 'ef'
  #     end
  #     string :s, read_length: 5
  #   end
  #
  #   obj = B.read("abcdefghij")
  #   obj.s #=> "efghi"
  #
  #
  # == Parameters
  #
  # Skip objects accept all the params that BinData::BasePrimitive
  # does, as well as the following:
  #
  # <tt>:length</tt>::        The number of bytes to skip.
  # <tt>:to_abs_offset</tt>:: Skips to the given absolute offset.
  # <tt>:until_valid</tt>::   Skips until a given byte pattern is matched.
  #                           This parameter contains a type that will raise
  #                           a BinData::ValidityError unless an acceptable byte
  #                           sequence is found.  The type is represented by a
  #                           Symbol, or if the type is to have params
  #                           passed to it, then it should be provided as
  #                           <tt>[type_symbol, hash_params]</tt>.
  #
  class Skip < BinData::BasePrimitive
    extend DSLMixin

    dsl_parser    :skip
    arg_processor :skip

    optional_parameters :length, :to_abs_offset, :until_valid
    mutually_exclusive_parameters :length, :to_abs_offset, :until_valid

    def initialize_shared_instance
      extend SkipLengthPlugin      if has_parameter?(:length)
      extend SkipToAbsOffsetPlugin if has_parameter?(:to_abs_offset)
      extend SkipUntilValidPlugin  if has_parameter?(:until_valid)
      super
    end

    #---------------
    private

    def value_to_binary_string(_)
      len = skip_length
      if len.negative?
        raise ArgumentError,
              "#{debug_name} attempted to seek backwards by #{len.abs} bytes"
      end

      "\000" * skip_length
    end

    def read_and_return_value(io)
      len = skip_length
      if len.negative?
        raise ArgumentError,
              "#{debug_name} attempted to seek backwards by #{len.abs} bytes"
      end

      io.skipbytes(len)
      ""
    end

    def sensible_default
      ""
    end

    # Logic for the :length parameter
    module SkipLengthPlugin
      def skip_length
        eval_parameter(:length)
      end
    end

    # Logic for the :to_abs_offset parameter
    module SkipToAbsOffsetPlugin
      def skip_length
        eval_parameter(:to_abs_offset) - abs_offset
      end
    end

    # Logic for the :until_valid parameter
    module SkipUntilValidPlugin
      def skip_length
        @skip_length ||= 0
      end

      def read_and_return_value(io)
        prototype = get_parameter(:until_valid)
        validator = prototype.instantiate(nil, self)
        fs = fast_search_for_obj(validator)

        io.transform(ReadaheadIO.new) do |transformed_io, raw_io|
          pos = 0
          loop do
            seek_to_pos(pos, raw_io)
            validator.clear
            validator.do_read(transformed_io)
            break
          rescue ValidityError
            pos += 1

            if fs
              seek_to_pos(pos, raw_io)
              pos += next_search_index(raw_io, fs)
            end
          end

          seek_to_pos(pos, raw_io)
          @skip_length = pos
        end
      end

      def seek_to_pos(pos, io)
        io.rollback
        io.skip(pos)
      end

      # A fast search has a pattern string at a specific offset.
      FastSearch = ::Struct.new('FastSearch', :pattern, :offset)

      def fast_search_for(obj)
        if obj.respond_to?(:asserted_binary_s)
          FastSearch.new(obj.asserted_binary_s, obj.rel_offset)
        else
          nil
        end
      end

      # If a search object has an +asserted_value+ field then we
      # perform a faster search for a valid object.
      def fast_search_for_obj(obj)
        if BinData::Struct === obj
          obj.each_pair(true) do |_, field|
            fs = fast_search_for(field)
            return fs if fs
          end
        elsif BinData::BasePrimitive === obj
          return fast_search_for(obj)
        end

        nil
      end

      SEARCH_SIZE = 100_000

      def next_search_index(io, fs)
        buffer = binary_string("")

        # start searching at fast_search offset
        pos = fs.offset
        io.skip(fs.offset)

        loop do
          data = io.read(SEARCH_SIZE)
          raise EOFError, "no match" if data.nil?

          buffer << data
          index = buffer.index(fs.pattern)
          if index
            return pos + index - fs.offset
          end

          # advance buffer
          searched = buffer.slice!(0..-fs.pattern.size)
          pos += searched.size
        end
      end

      class ReadaheadIO < BinData::IO::Transform
        def before_transform
          if !seekable?
            raise IOError, "readahead is not supported on unseekable streams"
          end

          @mark = offset
        end

        def rollback
          seek_abs(@mark)
        end
      end
    end
  end

  class SkipArgProcessor < BaseArgProcessor
    def sanitize_parameters!(obj_class, params)
      params.merge!(obj_class.dsl_params)

      unless params.has_at_least_one_of?(:length, :to_abs_offset, :until_valid)
        raise ArgumentError,
              "#{obj_class} requires :length, :to_abs_offset or :until_valid"
      end

      params.must_be_integer(:to_abs_offset, :length)
      params.sanitize_object_prototype(:until_valid)
    end
  end
end
