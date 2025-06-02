# frozen_string_literal: true

require_relative "elements"

module Gem
  module SafeMarshal
    class Reader
      class Error < StandardError
      end

      class UnsupportedVersionError < Error
      end

      class UnconsumedBytesError < Error
      end

      class NotImplementedError < Error
      end

      class EOFError < Error
      end

      def initialize(io)
        @io = io
      end

      def read!
        read_header
        root = read_element
        raise UnconsumedBytesError unless @io.eof?
        root
      end

      private

      MARSHAL_VERSION = [Marshal::MAJOR_VERSION, Marshal::MINOR_VERSION].map(&:chr).join.freeze
      private_constant :MARSHAL_VERSION

      def read_header
        v = @io.read(2)
        raise UnsupportedVersionError, "Unsupported marshal version #{v.bytes.map(&:ord).join(".")}, expected #{Marshal::MAJOR_VERSION}.#{Marshal::MINOR_VERSION}" unless v == MARSHAL_VERSION
      end

      def read_byte
        @io.getbyte
      end

      def read_integer
        b = read_byte

        case b
        when 0x00
          0
        when 0x01
          read_byte
        when 0x02
          read_byte | (read_byte << 8)
        when 0x03
          read_byte | (read_byte << 8) | (read_byte << 16)
        when 0x04
          read_byte | (read_byte << 8) | (read_byte << 16) | (read_byte << 24)
        when 0xFC
          read_byte | (read_byte << 8) | (read_byte << 16) | (read_byte << 24) | -0x100000000
        when 0xFD
          read_byte | (read_byte << 8) | (read_byte << 16) | -0x1000000
        when 0xFE
          read_byte | (read_byte << 8) | -0x10000
        when 0xFF
          read_byte | -0x100
        when nil
          raise EOFError, "Unexpected EOF"
        else
          signed = (b ^ 128) - 128
          if b >= 128
            signed + 5
          else
            signed - 5
          end
        end
      end

      def read_element
        type = read_byte
        case type
        when 34 then read_string # ?"
        when 48 then read_nil # ?0
        when 58 then read_symbol # ?:
        when 59 then read_symbol_link # ?;
        when 64 then read_object_link # ?@
        when 70 then read_false # ?F
        when 73 then read_object_with_ivars # ?I
        when 84 then read_true # ?T
        when 85 then read_user_marshal # ?U
        when 91 then read_array # ?[
        when 102 then read_float # ?f
        when 105 then Elements::Integer.new(read_integer) # ?i
        when 108 then read_bignum # ?l
        when 111 then read_object # ?o
        when 117 then read_user_defined # ?u
        when 123 then read_hash # ?{
        when 125 then read_hash_with_default_value # ?}
        when 101 then read_extended_object # ?e
        when 99 then read_class # ?c
        when 109 then read_module # ?m
        when 77 then read_class_or_module # ?M
        when 100 then read_data # ?d
        when 47 then read_regexp # ?/
        when 83 then read_struct # ?S
        when 67 then read_user_class # ?C
        when nil
          raise EOFError, "Unexpected EOF"
        else
          raise Error, "Unknown marshal type discriminator #{type.chr.inspect} (#{type})"
        end
      end

      STRING_E_SYMBOL = Elements::Symbol.new("E").freeze
      private_constant :STRING_E_SYMBOL

      def read_symbol
        len = read_integer
        if len == 1
          byte = read_byte
          if byte == 69 # ?E
            STRING_E_SYMBOL
          else
            Elements::Symbol.new(byte.chr)
          end
        else
          name = -@io.read(len)
          Elements::Symbol.new(name)
        end
      end

      EMPTY_STRING = Elements::String.new("".b.freeze).freeze
      private_constant :EMPTY_STRING

      def read_string
        length = read_integer
        return EMPTY_STRING if length == 0
        str = @io.read(length)
        Elements::String.new(str)
      end

      def read_true
        Elements::True::TRUE
      end

      def read_false
        Elements::False::FALSE
      end

      def read_user_defined
        name = read_element
        binary_string = @io.read(read_integer)
        Elements::UserDefined.new(name, binary_string)
      end

      EMPTY_ARRAY = Elements::Array.new([].freeze).freeze
      private_constant :EMPTY_ARRAY

      def read_array
        length = read_integer
        return EMPTY_ARRAY if length == 0
        elements = Array.new(length) do
          read_element
        end
        Elements::Array.new(elements)
      end

      def read_object_with_ivars
        object = read_element
        ivars = Array.new(read_integer) do
          [read_element, read_element]
        end
        Elements::WithIvars.new(object, ivars)
      end

      def read_symbol_link
        offset = read_integer
        Elements::SymbolLink.new(offset)
      end

      def read_user_marshal
        name = read_element
        data = read_element
        Elements::UserMarshal.new(name, data)
      end

      # profiling bundle install --full-index shows that
      # offset 6 is by far the most common object link,
      # so we special case it to avoid allocating a new
      # object a third of the time.
      # the following are all the object links that
      # appear more than 10000 times in my profiling

      OBJECT_LINKS = {
        6 => Elements::ObjectLink.new(6).freeze,
        30 => Elements::ObjectLink.new(30).freeze,
        81 => Elements::ObjectLink.new(81).freeze,
        34 => Elements::ObjectLink.new(34).freeze,
        38 => Elements::ObjectLink.new(38).freeze,
        50 => Elements::ObjectLink.new(50).freeze,
        91 => Elements::ObjectLink.new(91).freeze,
        42 => Elements::ObjectLink.new(42).freeze,
        46 => Elements::ObjectLink.new(46).freeze,
        150 => Elements::ObjectLink.new(150).freeze,
        100 => Elements::ObjectLink.new(100).freeze,
        104 => Elements::ObjectLink.new(104).freeze,
        108 => Elements::ObjectLink.new(108).freeze,
        242 => Elements::ObjectLink.new(242).freeze,
        246 => Elements::ObjectLink.new(246).freeze,
        139 => Elements::ObjectLink.new(139).freeze,
        143 => Elements::ObjectLink.new(143).freeze,
        114 => Elements::ObjectLink.new(114).freeze,
        308 => Elements::ObjectLink.new(308).freeze,
        200 => Elements::ObjectLink.new(200).freeze,
        54 => Elements::ObjectLink.new(54).freeze,
        62 => Elements::ObjectLink.new(62).freeze,
        1_286_245 => Elements::ObjectLink.new(1_286_245).freeze,
      }.freeze
      private_constant :OBJECT_LINKS

      def read_object_link
        offset = read_integer
        OBJECT_LINKS[offset] || Elements::ObjectLink.new(offset)
      end

      EMPTY_HASH = Elements::Hash.new([].freeze).freeze
      private_constant :EMPTY_HASH

      def read_hash
        length = read_integer
        return EMPTY_HASH if length == 0
        pairs = Array.new(length) do
          [read_element, read_element]
        end
        Elements::Hash.new(pairs)
      end

      def read_hash_with_default_value
        pairs = Array.new(read_integer) do
          [read_element, read_element]
        end
        default = read_element
        Elements::HashWithDefaultValue.new(pairs, default)
      end

      def read_object
        name = read_element
        object = Elements::Object.new(name)
        ivars = Array.new(read_integer) do
          [read_element, read_element]
        end
        Elements::WithIvars.new(object, ivars)
      end

      def read_nil
        Elements::Nil::NIL
      end

      def read_float
        string = @io.read(read_integer)
        Elements::Float.new(string)
      end

      def read_bignum
        sign = read_byte
        data = @io.read(read_integer * 2)
        Elements::Bignum.new(sign, data)
      end

      def read_extended_object
        raise NotImplementedError, "Reading Marshal objects of type extended_object is not implemented"
      end

      def read_class
        raise NotImplementedError, "Reading Marshal objects of type class is not implemented"
      end

      def read_module
        raise NotImplementedError, "Reading Marshal objects of type module is not implemented"
      end

      def read_class_or_module
        raise NotImplementedError, "Reading Marshal objects of type class_or_module is not implemented"
      end

      def read_data
        raise NotImplementedError, "Reading Marshal objects of type data is not implemented"
      end

      def read_regexp
        raise NotImplementedError, "Reading Marshal objects of type regexp is not implemented"
      end

      def read_struct
        raise NotImplementedError, "Reading Marshal objects of type struct is not implemented"
      end

      def read_user_class
        name = read_element
        wrapped_object = read_element
        Elements::UserClass.new(name, wrapped_object)
      end
    end
  end
end
