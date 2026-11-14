# frozen_string_literal: true

require_relative "binary_encoding"

module Protobug
  class Field
    PACKABLE_WIRE_TYPES = [0, 1, 5].freeze

    attr_accessor :number, :name, :json_name, :cardinality, :oneof, :ivar, :setter,
                  :adder, :haser, :clearer

    def initialize(number, name, json_name: nil, cardinality: :optional, oneof: nil, packed: false,
                   proto3_optional: cardinality == :optional)
      @number = number
      @name = name.to_sym
      @json_name = json_name || name.to_s
      @cardinality = cardinality || raise(ArgumentError, "cardinality is required")
      @oneof = oneof
      @setter = :"#{name}="
      @adder = :"add_#{name}" if repeated?
      @ivar = :"@#{name}"
      @clearer = :"clear_#{name}"
      @haser = :"#{name}?"
      @packed = packed
      @proto3_optional = proto3_optional
    end

    def pretty_print(pp)
      pp.group 0, "#{self.class}.new(", ")" do
        pp.text @number.to_s
        pp.breakable(", ")
        pp.text(@name.inspect)
        pp.breakable(", ")
        if json_name != name.name
          pp.breakable(", ")
          pp.text("json_name: ")
          pp.text(@json_name.inspect)
        end
        pp.breakable(", ")
        pp.text("cardinality: ")
        pp.pp(@cardinality)
        if oneof
          pp.breakable(", ")
          pp.text("oneof: ")
          pp.text(@oneof.inspect)
        end
      end
    end

    def repeated?
      cardinality == :repeated
    end

    def packed?
      @packed
    end

    def optional?
      cardinality == :optional
    end

    def proto3_optional?
      @proto3_optional
    end

    def method_definitions
      str = +""

      str << "def #{setter}(value)\n"
      str << "  return #{ivar} = ::Protobug::UNSET if value.nil?\n" if optional? && proto3_optional?
      str << "  field = self.class.fields_by_name.fetch(#{name.to_s.dump})\n"
      str << "  field.validate!(value, self)\n"
      str << "  #{ivar} = value\n"
      str << "end\n"

      str << "def #{name}\n"
      str << "  value = #{ivar}\n"
      str << "  ::Protobug::UNSET == value ? self.class.fields_by_name.fetch(#{name.to_s.dump}).default : value\n"
      str << "end\n"

      str << "def #{haser}\n"
      str << "  value = #{ivar}\n"
      str << "  return false if ::Protobug::UNSET == value\n"
      if (!optional? || !proto3_optional?) && !oneof
        str << "  field = self.class.fields_by_name.fetch(#{name.to_s.dump})\n"
        str << "  return false if field.default == value\n"
      end
      str << if repeated?
               "  !value.empty?\n"
             else
               "  true\n"
             end
      str << "end\n"

      str << "def #{clearer}\n"
      str << "  #{ivar} = ::Protobug::UNSET\n"
      str << "end\n"

      adder_method_definition(str) if repeated?

      str
    end

    def adder_method_definition(str)
      str << "def #{adder}(value)\n"
      str << "  existing = #{ivar}\n"
      str << "  field = self.class.fields_by_name.fetch(#{name.to_s.dump})\n"
      str << "  if ::Protobug::UNSET == existing\n"
      str << "    existing = field.default\n"
      str << "    #{ivar} = existing\n"
      str << "  end\n"
      str << "  field.validate!(value, self)\n"
      str << "  existing << value\n"
      str << "end\n"
    end

    def to_text(value)
      case [cardinality, json_scalar?]
      when [:repeated, true]
        Array(value).map { |v| "#{name}: #{scalar_to_text(v)}" }.join("\n")
      when [:repeated, false]
        Array(value).map { |v| "#{name} {\n#{v.to_text.gsub(/^/, "  ")}\n}" }.join("\n")
      when [:optional, true]
        "#{name}: #{scalar_to_text(value)}"
      when [:optional, false]
        "#{name} {\n#{value.to_text.gsub(/^/, "  ")}\n}"
      end
    end

    def binary_encode(value, outbuf)
      if repeated?
        if packed?
          binary_encode_packed(value, outbuf)
        else
          value.each do |v|
            BinaryEncoding.encode_varint (number << 3) | wire_type, outbuf
            binary_encode_one(v, outbuf)
          end
        end
      elsif (!optional? || !proto3_optional?) && !oneof && default == value
        # omit
      else
        BinaryEncoding.encode_varint (number << 3) | wire_type, outbuf
        binary_encode_one(value, outbuf)
      end
    end

    def binary_decode(binary, message, registry, wire_type)
      own_wire_type = self.wire_type
      if repeated? && wire_type == 2 && PACKABLE_WIRE_TYPES.include?(own_wire_type)
        len = StringIO.new(BinaryEncoding.decode_length(binary))
        len.binmode

        message.send(adder, binary_decode_one(len, message, registry, own_wire_type)) until len.eof?
      elsif wire_type != own_wire_type
        raise DecodeError, "wrong wire type for #{self}: #{wire_type.inspect}"
      else
        message.send(adder || setter, binary_decode_one(binary, message, registry, wire_type))
      end
    end

    def json_encode(value, print_unknown_fields:)
      if repeated?
        value.map { |v| json_encode_one(v, print_unknown_fields: print_unknown_fields) }
      elsif (!optional? || !proto3_optional?) && !oneof && default == value
        # omit
      else
        json_encode_one(value, print_unknown_fields: print_unknown_fields)
      end
    end

    def json_key_encode(value)
      case value
      when String
        value
      when Integer, Float
        value.to_s
      when TrueClass
        "true"
      when FalseClass
        "false"
      else
        raise EncodeError, "unexpected type for map key: #{value.inspect}"
      end
    end

    def json_decode(value, message, ignore_unknown_fields, registry)
      if repeated?
        return if value.nil?

        unless value.is_a?(Array)
          raise DecodeError,
                "expected Array for #{inspect}, got #{value.inspect}"
        end

        value.map do |v|
          message.send(adder, json_decode_one(v, ignore_unknown_fields, registry))
        end
      else
        value = json_decode_one(value, ignore_unknown_fields, registry)
        message.send(setter, value) unless UNSET == value
      end
    end

    def validate!(value, message)
      raise DecodeError, "nil is invalid for #{name} in #{message}" if UNSET == value

      return unless oneof

      message.class.oneofs[oneof].each do |f|
        next if f == self

        message.send(f.clearer)
      end
    end

    private

    def binary_encode_packed(value, outbuf)
      BinaryEncoding.encode_varint (number << 3) | 2, outbuf

      BinaryEncoding.encode_length(value.each_with_object("".b) do |v, buf|
        binary_encode_one(v, buf)
      end, outbuf)
    end

    class MessageField < Field
      attr_reader :message_type

      def initialize(number, name, cardinality:, message_type:, json_name: name, oneof: nil,
                     proto3_optional: cardinality == :optional)
        super(number, name, json_name: json_name, cardinality: cardinality, oneof: oneof,
                            proto3_optional: proto3_optional)
        @message_type = message_type
      end

      def binary_encode_one(value, outbuf)
        BinaryEncoding.encode_length value.class.encode(value), outbuf
      end

      def binary_decode_one(io, message, registry, wire_type)
        value = BinaryEncoding.read_field_value(io, wire_type)
        kwargs = {}
        kwargs[:object] = message.send(name) if !repeated? && message.send(haser)
        type_lookup(registry).decode(StringIO.new(value), registry: registry, **kwargs)
      end

      def json_decode_one(value, ignore_unknown_fields, registry)
        klass = type_lookup(registry)
        klass.decode_json_hash(value, registry: registry, ignore_unknown_fields: ignore_unknown_fields)
      end

      def type_lookup(registry)
        registry.fetch(message_type)
      end

      def json_encode_one(value, print_unknown_fields:)
        value.as_json(print_unknown_fields: print_unknown_fields)
      end

      def default
        return [] if repeated?

        # TODO: message_type.default
        nil
      end

      def wire_type
        2
      end
    end

    class MapField < MessageField
      SUPER_INITIALIZE = instance_method(:initialize).super_method
      def initialize(number, name, key_type:, value_type:, json_name: name, oneof: nil, # rubocop:disable Lint/MissingSuper,
                     enum_type: nil, message_type: nil)
        SUPER_INITIALIZE.bind_call(
          self, number, name,
          cardinality: :repeated,
          json_name: json_name,
          oneof: oneof
        )

        @map_class = Class.new do
          extend Protobug::Message

          optional(1, "key", type: key_type, proto3_optional: false)
          value_type_kwargs = { enum_type: enum_type, message_type: message_type }
          value_type_kwargs.compact!
          optional(2, "value", type: value_type, **value_type_kwargs, proto3_optional: false)
        end
      end

      def repeated
        true
      end

      def default
        {}
      end

      def repeated?
        true
      end

      def binary_encode(value, outbuf)
        value.each_with_object(@map_class.new) do |(k, v), entry|
          entry.key = k
          entry.value = v
          BinaryEncoding.encode_varint (number << 3) | wire_type, outbuf
          BinaryEncoding.encode_length @map_class.encode(entry), outbuf
        end
      end

      def json_encode(value, print_unknown_fields:)
        value.to_h do |k, v|
          value = @map_class.fields_by_name["value"].json_encode(v, print_unknown_fields: print_unknown_fields)
          [json_key_encode(k), value]
        end
      end

      def json_decode(value, message, ignore_unknown_fields, registry)
        return if value.nil?

        unless value.is_a?(Hash)
          raise DecodeError,
                "expected Hash for #{inspect}, got #{value.inspect}"
        end

        value.each do |k, v|
          entry = @map_class.decode_json_hash(
            { "key" => k, "value" => v },
            registry: registry,
            ignore_unknown_fields: ignore_unknown_fields
          )
          # can't use haser because default values should also be counted...
          if UNSET == entry.instance_variable_get(:@value)
            next if ignore_unknown_fields && @map_class.fields_by_name.fetch("value").is_a?(EnumField)

            raise DecodeError, "nil values are not allowed in map #{name} in #{message.class}"
          end

          message.send(adder, entry)
        end
      end

      def type_lookup(_registry)
        @map_class
      end

      def adder_method_definition(str)
        str << "def #{adder}(msg)\n"
        str << "  existing = #{ivar}\n"
        str << "  if ::Protobug::UNSET == existing\n"
        str << "    existing = {}\n"
        str << "    #{ivar} = existing\n"
        str << "  end\n"
        str << "  existing[msg.key] = msg.value\n"
        str << "end\n"
      end
    end

    class BytesField < Field
      def self.type
        :bytes
      end

      def initialize(number, name, cardinality:, json_name: name, oneof: nil,
                     proto3_optional: cardinality == :optional)
        super(number, name, json_name: json_name, cardinality: cardinality, oneof: oneof,
                            proto3_optional: proto3_optional)
      end

      def binary_encode_one(value, outbuf)
        BinaryEncoding.encode_length value.b, outbuf
      end

      def binary_decode_one(io, _message, _registry, wire_type)
        BinaryEncoding.read_field_value(io, wire_type)
      end

      def json_decode_one(value, _ignore_unknown_fields, _registry)
        return UNSET if value.nil?

        # url decode 64
        value.tr!("-_", "+/")
        begin
          value = value.unpack1("m").force_encoding(Encoding::BINARY)
        rescue ArgumentError => e
          raise DecodeError, "Invalid URL-encoded base64 #{value.inspect} for #{inspect}: #{e}"
        end

        value
      end

      def json_encode_one(value, print_unknown_fields:) # rubocop:disable Lint/UnusedMethodArgument
        [value].pack("m0")
      end

      def default
        return [] if repeated?

        "".b
      end

      def wire_type
        2
      end
    end

    class StringField < BytesField
      def self.type
        :string
      end

      def initialize(number, name, cardinality:, json_name: name, oneof: nil,
                     proto3_optional: cardinality == :optional)
        super(number, name, json_name: json_name, cardinality: cardinality, oneof: oneof,
                            proto3_optional: proto3_optional)
      end

      def binary_encode_one(value, outbuf)
        value = value.encode("utf-8") if value.encoding != Encoding::UTF_8
        super
      end

      def binary_decode_one(io, _message, _registry, wire_type)
        value = super

        value.force_encoding("utf-8") if value.encoding != Encoding::UTF_8
        raise DecodeError, "invalid utf-8 for string" unless value.valid_encoding?

        value
      end

      def json_decode_one(value, _ignore_unknown_fields, _registry)
        return UNSET if value.nil?
        raise DecodeError, "expected string, got #{value.inspect}" unless value.is_a?(String)

        value.force_encoding("utf-8") if value.encoding != Encoding::UTF_8
        raise DecodeError, "invalid utf-8 for string" unless value.valid_encoding?

        value
      end

      def json_encode_one(value, print_unknown_fields:) # rubocop:disable Lint/UnusedMethodArgument
        value.encode("utf-8")
      end

      def default
        return [] if repeated?

        +""
      end
    end

    class IntegerField < Field
      def default
        return [] if repeated?

        0
      end

      def binary_decode_one(io, _message, _registry, wire_type)
        value = BinaryEncoding.read_field_value(io, wire_type)
        case encoding
        when :zigzag
          BinaryEncoding.decode_zigzag bit_length, value
        when :varint
          length_mask = (2**bit_length) - 1
          negative = signed && value & (2**bit_length.pred) != 0
          if negative
            value &= length_mask # remove sign bit

            # 2's complement
            value ^= length_mask
            value += 1
            -value
          else
            value & length_mask
          end
        when :fixed
          value.unpack1(binary_pack)
        end
      end

      def binary_encode_one(value, outbuf)
        case encoding
        when :zigzag
          BinaryEncoding.encode_zigzag bit_length, value, outbuf
        when :varint
          BinaryEncoding.encode_varint value, outbuf
        when :fixed
          BinaryEncoding.pack([value], binary_pack, buffer: outbuf)
        end
      end

      def json_decode_one(value, _ignore_unknown_fields, _registry)
        return UNSET if value.nil?

        case value
        when Integer
          # nothing
        when /\A-?\d+\z/
          value = Integer(value)
        when Float
          int, remainder = value.divmod(1)
          raise DecodeError, "expected integer for #{inspect}, got #{value.inspect}" unless remainder == 0

          value = int
        else
          raise DecodeError, "expected integer for #{inspect}, got #{value.inspect}"
        end
        raise DecodeError, "#{value.inspect} does not fit in 64 bits" if value && value.bit_length > 64

        value
      end

      def json_encode_one(value, print_unknown_fields:) # rubocop:disable Lint/UnusedMethodArgument
        if bit_length >= 64
          value.to_s
        else
          value
        end
      end

      def validate!(value, message)
        raise InvalidValueError.new(message, self, value, "expected integer") unless value.is_a?(Integer)

        if signed
          min = -2**(bit_length - 1)
          max = 2**(bit_length - 1)
        else
          min = 0
          max = 2**bit_length
        end

        if value < min || value >= max
          raise InvalidValueError.new(message, self, value, "does not fit into [#{min}, #{max})")
        end

        super
      end
    end

    # encoding: fixed, varint, zigzag
    # bitlength: 32, 64
    # signed: true, false
    # EXCEPT: no unsigned zigzag
    class Int64Field < IntegerField
      def encoding
        :varint
      end

      def bit_length
        64
      end

      def signed
        true
      end

      def wire_type
        0
      end
    end

    class UInt64Field < IntegerField
      def encoding
        :varint
      end

      def bit_length
        64
      end

      def signed
        false
      end

      def wire_type
        0
      end
    end

    class SInt64Field < IntegerField
      def encoding
        :zigzag
      end

      def bit_length
        64
      end

      def signed
        true
      end

      def wire_type
        0
      end
    end

    class Fixed64Field < IntegerField
      def encoding
        :fixed
      end

      def bit_length
        64
      end

      def signed
        false
      end

      def wire_type
        1
      end

      def binary_pack
        "Q<"
      end
    end

    class SFixed64Field < IntegerField
      def encoding
        :fixed
      end

      def bit_length
        64
      end

      def signed
        true
      end

      def wire_type
        1
      end

      def binary_pack
        "q<"
      end
    end

    class Int32Field < IntegerField
      def encoding
        :varint
      end

      def bit_length
        32
      end

      def signed
        true
      end

      def wire_type
        0
      end
    end

    class UInt32Field < IntegerField
      def encoding
        :varint
      end

      def bit_length
        32
      end

      def signed
        false
      end

      def wire_type
        0
      end
    end

    class SInt32Field < IntegerField
      def encoding
        :zigzag
      end

      def bit_length
        32
      end

      def signed
        true
      end

      def wire_type
        0
      end
    end

    class Fixed32Field < IntegerField
      def encoding
        :fixed
      end

      def bit_length
        32
      end

      def signed
        false
      end

      def wire_type
        5
      end

      def binary_pack
        "V"
      end
    end

    class SFixed32Field < IntegerField
      def encoding
        :fixed
      end

      def bit_length
        32
      end

      def signed
        true
      end

      def wire_type
        5
      end

      def binary_pack
        "l<"
      end
    end

    class BoolField < UInt64Field
      def binary_decode_one(*)
        super != 0
      end

      def binary_encode_one(value, outbuf)
        super(value ? 1 : 0, outbuf)
      end

      def json_decode_one(value, _ignore_unknown_fields, _registry)
        case value
        when TrueClass, FalseClass
          value
        when "true"
          true
        when "false"
          false
        when NilClass
          UNSET
        else
          raise DecodeError, "expected boolean, got #{value.inspect}"
        end
      end

      def validate!(value, message)
        raise InvalidValueError.new(message, self, value, "expected boolean") unless [true, false].include?(value)

        super(value ? 1 : 0, message)
      end

      def default
        return [] if repeated?

        false
      end
    end

    class EnumField < Int32Field
      attr_reader :enum_type

      def initialize(number, name, cardinality:, enum_type:, json_name: name, oneof: nil, packed: false,
                     proto3_optional: cardinality == :optional)
        super(number, name, json_name: json_name, cardinality: cardinality, oneof: oneof,
                            proto3_optional: proto3_optional, packed: packed)
        @enum_type = enum_type
      end

      def json_decode(value, message, ignore_unknown_fields, registry)
        return super unless ignore_unknown_fields

        if repeated?
          return if value.nil?

          unless value.is_a?(Array)
            raise DecodeError,
                  "expected Array for #{inspect}, got #{value.inspect}"
          end

          value.map do |v|
            v = json_decode_one(v, ignore_unknown_fields, registry)
            next if UNSET == v

            message.send(adder, v)
          end.tap(&:compact!)
        else
          value = json_decode_one(value, ignore_unknown_fields, registry)
          message.send(setter, value) unless UNSET == value
        end
      end

      def binary_encode_one(value, outbuf)
        super(value.value, outbuf)
      end

      def binary_decode_one(io, _message, registry, wire_type)
        value = super
        registry.fetch(enum_type).decode(value)
      end

      def json_decode_one(value, ignore_unknown_fields, registry)
        klass = registry.fetch(enum_type)
        klass.decode_json_hash(value, registry: registry, ignore_unknown_fields: ignore_unknown_fields)
      end

      def json_encode_one(value, print_unknown_fields:) # rubocop:disable Lint/UnusedMethodArgument
        value.as_json
      end

      def default
        return [] if repeated?

        # TODO: enum_type.default
        0
      end

      def validate!(value, message)
        value = value.value if value.is_a?(Enum::InstanceMethods)
        super
      end
    end

    class DoubleField < Field
      def type
        :double
      end

      def binary_pack
        "E"
      end

      def wire_type
        1
      end

      def initialize(number, name, cardinality:, json_name: name, oneof: nil, packed: false,
                     proto3_optional: cardinality == :optional)
        super(number, name, json_name: json_name, cardinality: cardinality, oneof: oneof,
                            proto3_optional: proto3_optional, packed: packed)
      end

      def binary_encode_one(value, outbuf)
        BinaryEncoding.pack([value], binary_pack, buffer: outbuf)
      end

      def binary_decode_one(io, _message, _registry, wire_type)
        value = BinaryEncoding.read_field_value(io, wire_type)
        value.unpack1(binary_pack)
      end

      def json_decode_one(value, _ignore_unknown_fields, _registry)
        case value
        when Float
          value
        when Integer
          value.to_f
        when "Infinity"
          Float::INFINITY
        when "-Infinity"
          -Float::INFINITY
        when "NaN"
          Float::NAN
        when /\A-?(?:\d+(?:\.\d+)?|\.\d+)(?:[eE][-+]?\d+)?\z/
          Float(value)
        when NilClass
          UNSET
        else
          raise DecodeError, "expected float for #{inspect}, got #{value.inspect}"
        end
      end

      def json_encode_one(value, print_unknown_fields:) # rubocop:disable Lint/UnusedMethodArgument
        if value.nan?
          "NaN"
        elsif (sign = value.infinite?)
          if sign == -1
            "-Infinity"
          else
            "Infinity"
          end
        else
          value
        end
      end

      def default
        return [] if repeated?

        0.0
      end
    end

    class FloatField < DoubleField
      def type
        :float
      end

      def binary_pack
        "e"
      end

      def wire_type
        5
      end
    end

    class GroupField < Field
      def initialize(*args, group_type:, **kwargs)
        _ = group_type
        super(*args, **kwargs)
      end
    end
  end
end
