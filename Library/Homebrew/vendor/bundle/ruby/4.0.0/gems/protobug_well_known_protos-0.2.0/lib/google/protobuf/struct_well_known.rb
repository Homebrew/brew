# frozen_string_literal: true

Google::Protobuf::Value.class_eval do
  class self::UnexpectedStructType < Protobug::InvalidValueError # rubocop:disable Lint/ConstantDefinitionInBlock,Style/ClassAndModuleChildren
  end

  def to_ruby(recursive: false)
    case kind
    when :struct_value
      if recursive
        struct_value.to_h
      else
        struct_value
      end
    when :list_value
      if recursive
        list_value.to_a
      else
        list_value
      end
    when :null_value
      nil
    when :number_value
      number_value
    when :string_value
      string_value
    when :bool_value
      bool_value
    else
      raise UnexpectedStructType
    end
  end

  def self.from_ruby(value)
    new.from_ruby(value)
  end

  def from_ruby(value)
    case value
    when NilClass
      self.null_value = Google::Protobuf::NullValue::NULL_VALUE
    when Numeric
      self.number_value = value
    when String
      self.string_value = value
    when TrueClass
      self.bool_value = true
    when FalseClass
      self.bool_value = false
    when Struct
      self.struct_value = value
    when Hash
      self.struct_value = Struct.from_hash(value)
    when ListValue
      self.list_value = value
    when Array
      self.list_value = ListValue.from_a(value)
    else
      raise UnexpectedStructType
    end

    self
  end

  def self.decode_json_hash(json, registry:, ignore_unknown_fields: false)
    case json
    when NilClass
      json = { "nullValue" => "NULL_VALUE" }
    when Float, Integer
      json = { "numberValue" => json.to_f }
    when String
      json = { "stringValue" => json }
    when TrueClass, FalseClass
      json = { "boolValue" => json }
    when Hash
      json = { "structValue" => json }
    when Array
      json = { "listValue" => json }
    end

    super
  end

  def as_json(print_unknown_fields: false)
    case kind
    when :null_value
      nil
    when :number_value
      number_value
    when :string_value
      string_value
    when :bool_value
      bool_value
    when :struct_value
      struct_value.as_json(print_unknown_fields: print_unknown_fields)
    when :list_value
      list_value.values.map! { _1.as_json(print_unknown_fields: print_unknown_fields) }
    else
      raise Protobug::EncodeError, "unknown kind: #{kind.inspect}"
    end
  end
end

Google::Protobuf::Struct.class_eval do
  def [](key)
    fields[key]&.to_ruby
  end

  def []=(key, value)
    raise ArgumentError, "Struct keys must be strings." unless key.is_a?(String)

    fields[key] ||= Google::Protobuf::Value.new
    fields[key].from_ruby(value)
  end

  def to_h
    fields.transform_values { |val| val.to_ruby(true) }
  end

  def self.from_hash(hash)
    hash.each_with_object(new) { |(key, val), ret| ret[key] = val }
  end

  def key?(key)
    fields.key?(key)
  end

  def self.decode_json_hash(json, registry:, ignore_unknown_fields: false)
    json = { "fields" => json }
    super
  end

  def as_json(print_unknown_fields: false)
    fields.transform_values { _1&.as_json(print_unknown_fields: print_unknown_fields) }
  end
end

Google::Protobuf::ListValue.class_eval do
  include Enumerable

  def length
    values.length
  end

  def [](index)
    values[index].to_ruby
  end

  def []=(index, value)
    values[index].from_ruby(value)
  end

  def <<(value)
    values << Google::Protobuf::Value.from_ruby(value)
  end

  def each
    return enum_for(__method__) unless block_given?

    values.each { |x| yield(x.to_ruby) }
  end

  def to_a
    values.map { |x| x.to_ruby(true) }
  end

  def self.from_a(arr)
    arr.each_with_object(new) { |val, ret| ret << val }
  end

  def self.decode_json_hash(json, registry:, ignore_unknown_fields: false)
    json = { "values" => json }
    super
  end

  def as_json(print_unknown_fields: false)
    values.map { _1.as_json(print_unknown_fields: print_unknown_fields) }
  end
end

Google::Protobuf::NullValue.class_eval do
  def self.decode_json_hash(json, registry:, ignore_unknown_fields: false)
    return values.fetch(0) if json.nil?

    super
  end

  def as_json(print_unknown_fields: false)
    return if value == 0

    super
  end
end
