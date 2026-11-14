# frozen_string_literal: true

require_relative "binary_encoding"
require_relative "errors"
require_relative "field"
require "stringio"

module Protobug
  UNSET = Object.new
  def UNSET.inspect
    "<UNSET>"
  end

  def UNSET.to_s
    "<UNSET>"
  end

  def UNSET.===(other)
    other.equal? UNSET
  end
  UNSET.freeze

  module Message
    def self.extended(base)
      base.class_eval do
        @full_name = nil
        @fields_by_number = {}
        @fields_by_json_name = {}
        @fields_by_name = {}
        @reserved_ranges = []
        @oneofs = {}
        extend BaseDescriptor
        include Protobug::Message::InstanceMethods
      end
    end

    attr_accessor :full_name
    attr_reader :fields_by_number, :fields_by_name, :fields_by_json_name, :reserved_ranges, :oneofs

    def freeze
      fields_by_number.freeze
      fields_by_name.freeze
      fields_by_json_name.freeze
      full_name.freeze
      reserved_ranges.freeze
      oneofs.each_value(&:freeze)
      oneofs.freeze
      super
    end

    def optional(number, name, **kwargs)
      if kwargs[:cardinality] && kwargs[:cardinality] != :optional
        raise DefinitionError,
              "expected cardinality: :optional, got #{kwargs[:cardinality].inspect}"
      end
      field(number, name, cardinality: :optional, **kwargs)
    end

    def repeated(number, name, **kwargs)
      if kwargs[:cardinality] && kwargs[:cardinality] != :repeated
        raise DefinitionError,
              "expected cardinality: :repeated, got #{kwargs[:cardinality].inspect}"
      end
      field(number, name, cardinality: :repeated, **kwargs)
    end

    def map(number, name, **kwargs)
      if kwargs[:type] && kwargs[:type] != :map
        raise DefinitionError,
              "expected type: :map, got #{kwargs[:type].inspect}"
      end
      repeated(number, name, type: :map, **kwargs)
    end

    def required(number, name, **kwargs)
      if kwargs[:cardinality] && kwargs[:cardinality] != :required
        raise DefinitionError,
              "expected cardinality: :required, got #{kwargs[:cardinality].inspect}"
      end
      field(number, name, cardinality: :required, **kwargs)
    end

    def reserved_range(range)
      raise DefinitionError, "expected Range, got #{range.inspect}" unless range.is_a? Range

      reserved_ranges << range
    end

    def decode_json(json, registry:, ignore_unknown_fields: false)
      require "json"
      hash = begin
        JSON.parse(json, allow_blank: false, create_additions: false, allow_nan: false, allow_infinity: false)
      rescue JSON::ParserError => e
        raise DecodeError, "JSON failed to parse: #{e.message}"
      end
      raise DecodeError, "expected hash, got #{hash.inspect}" unless hash.is_a? Hash

      decode_json_hash(hash, registry: registry, ignore_unknown_fields: ignore_unknown_fields)
    end

    def decode_json_hash(json, registry:, ignore_unknown_fields: false)
      return UNSET if json.nil?
      raise DecodeError, "expected hash for #{self} (#{full_name}), got #{json.inspect}" unless json.is_a? Hash

      message = new

      json.each do |key, value|
        field = fields_by_json_name[key]
        unless field
          next if ignore_unknown_fields

          raise(UnknownFieldError, "unknown field #{key.inspect} in #{full_name}")
        end

        if field.oneof && message.send(field.oneof) && !value.nil?
          raise DecodeError, "multiple oneof fields set in #{full_name}: #{message.send(field.oneof)} and #{field.name}"
        end

        field.json_decode(value, message, ignore_unknown_fields, registry)
      end

      message
    end

    def decode(binary, registry:, object: new)
      binary.binmode
      while (header = BinaryEncoding.decode_varint(binary))
        wire_type = header & 0b111
        number = header >> 3

        unless number > 0
          raise DecodeError,
                "unexpected field number #{number} in #{full_name || fields_by_name.inspect}"
        end

        field = fields_by_number[number]

        if field
          field.binary_decode(binary, object, registry, wire_type)
        else
          object.unknown_fields << [number, wire_type, BinaryEncoding.read_field_value(binary, wire_type)]
        end
      end
      object
    end

    def encode(message)
      raise EncodeError, "expected #{self}, got #{message.inspect}" unless message.is_a? self

      buf = fields_by_number.each_with_object("".b) do |(_number, field), outbuf|
        next unless message.send(field.haser)

        value = message.instance_variable_get(field.ivar)

        field.binary_encode(value, outbuf)
      end
      message.unknown_fields.each_with_object(buf) do |(number, wire_type, value), outbuf|
        BinaryEncoding.encode_varint((number << 3) | wire_type, outbuf)
        case wire_type
        when 0
          BinaryEncoding.encode_varint(value, outbuf)
        when 1, 5
          outbuf << value
        when 2
          BinaryEncoding.encode_length(value, outbuf)
        else
          raise EncodeError, "unknown wire_type: #{wire_type}"
        end
      end
    end

    def field(number, name, type:, **kwargs)
      raise ArgumentError unless number.is_a? Integer

      case name
      when String
        # OK
      when Symbol
        name = name.name
      else
        raise ArgumentError
      end

      field =
        case type
        when :message
          Field::MessageField
        when :enum
          Field::EnumField
        when :bytes
          Field::BytesField
        when :string
          Field::StringField
        when :map
          kwargs.delete(:cardinality) if kwargs[:cardinality] == :repeated
          Field::MapField
        when :int64
          Field::Int64Field
        when :uint64
          Field::UInt64Field
        when :sint64
          Field::SInt64Field
        when :fixed64
          Field::Fixed64Field
        when :sfixed64
          Field::SFixed64Field
        when :int32
          Field::Int32Field
        when :uint32
          Field::UInt32Field
        when :sint32
          Field::SInt32Field
        when :fixed32
          Field::Fixed32Field
        when :sfixed32
          Field::SFixed32Field
        when :bool
          Field::BoolField
        when :float
          Field::FloatField
        when :double
          Field::DoubleField
        when :group
          Field::GroupField
        else
          raise ArgumentError, "Unknown field type #{type.inspect}"
        end.new(number, name, **kwargs).freeze

      raise DefinitionError, "duplicate field number #{number}" if fields_by_number[number]

      fields_by_number[number] = field
      raise DefinitionError, "duplicate field name #{name}" if fields_by_name[name]

      fields_by_name[name] = field

      fields_by_json_name[name] = field
      fields_by_json_name[field.json_name] = field

      class_eval(field.method_definitions, __FILE__, __LINE__)

      return unless field.oneof

      unless (oneof = oneofs[field.oneof])
        oneofs[field.oneof] = oneof = []
        define_method(field.oneof) do
          oneof.find { |f| send(f.haser) }&.name
        end
      end
      oneof << field
    end

    module InstanceMethods
      def ==(other)
        return false unless other.instance_of?(self.class)

        self.class.fields_by_name.all? do |name, _|
          send(name) == other.send(name)
        end
      end
      alias eql? ==

      attr_reader :unknown_fields

      def initialize
        super
        self.class.fields_by_name.each_value do |field|
          instance_variable_set(field.ivar, UNSET)
        end
        @unknown_fields = []
      end

      def pretty_print(pp)
        fields_with_values = self.class.fields_by_name.select do |_name, field|
          send(field.haser)
        end
        pp.group 2, "#{self.class}.new(", ")" do
          pp.breakable
          fields_with_values.each_with_index do |(name, field), idx|
            pp.nest 2 do
              unless idx == 0
                pp.text ","
                pp.breakable " "
              end
              pp.text "#{name}: "
              pp.pp send(field.name)
            end
          end
        end
      end

      def hash
        # Build a single array (map result is mutated in place via unshift) rather
        # than allocating both the mapped array and a second spread literal.
        values = self.class.fields_by_name.map { |name, _| send(name) }
        values.unshift(self.class)
        values.hash
      end

      def to_text
        fields_with_values = self.class.fields_by_name.select do |_name, field|
          send(field.haser)
        end

        fields_with_values.map do |_name, field|
          value = send(field.name)
          field.to_text(value)
        end.join("\n")
      end

      def to_proto
        self.class.encode(self)
      end

      def as_json(print_unknown_fields: false)
        fields_with_values = self.class.fields_by_name.select do |_name, field|
          send(field.haser)
        end

        fields_with_values.to_h do |_name, field|
          value = send(field.name)

          [field.json_name, field.json_encode(value, print_unknown_fields: print_unknown_fields)]
        end
      end

      def to_json(print_unknown_fields: false)
        require "json"
        JSON.generate(as_json(print_unknown_fields: print_unknown_fields), allow_infinity: true)
      rescue JSON::GeneratorError => e
        raise EncodeError, "failed to generate JSON: #{e}"
      end
    end
  end
end
