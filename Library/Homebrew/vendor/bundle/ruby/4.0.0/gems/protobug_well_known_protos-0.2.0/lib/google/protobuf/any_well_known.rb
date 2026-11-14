# frozen_string_literal: true

Google::Protobuf::Any.class_eval do
  def self.pack(msg)
    any = new
    any.pack(msg)
    any
  end

  def pack(msg)
    self.type_url = "type.googleapis.com/#{msg.class.full_name}"
    self.value = msg.to_proto
  end

  def unpack(registry)
    type = registry.fetch(type_url.delete_prefix("type.googleapis.com/"))
    type.decode(value, registry: registry)
  end

  def self.decode_json_hash(json, registry:, ignore_unknown_fields: false)
    raise Protobug::DecodeError, "expected hash, got #{json.inspect}" unless json.is_a? Hash

    json = json.dup
    type_url = json.delete("@type") || raise(Protobug::DecodeError, "missing @type")
    raise Protobug::DecodeError, "expected string for @type, got #{type_url.inspect}" unless type_url.is_a? String

    unless type_url.start_with?("type.googleapis.com/")
      raise Protobug::DecodeError, "only type.googleapis.com/ types are supported for Any"
    end

    # TODO: specifically check for well-known type with custom JSON representation
    json = json["value"] if json.key?("value") && json.size == 1

    type = registry.fetch(type_url.delete_prefix("type.googleapis.com/"))
    v = type.decode_json_hash(json, registry: registry, ignore_unknown_fields: ignore_unknown_fields)
    json = {
      "type_url" => type_url,
      "value" => [type.encode(v)].pack("m0")
    }
    super
  end

  def as_json(print_unknown_fields: false) # rubocop:disable Lint/UnusedMethodArgument
    # TODO: need a registry to look up the type
    raise Protobug::UnsupportedFeatureError.new(:any, "serializing to json")
    # return value.as_json.merge("@type" => "type.googleapis.com/#{value.class.full_name}")
  end
end
