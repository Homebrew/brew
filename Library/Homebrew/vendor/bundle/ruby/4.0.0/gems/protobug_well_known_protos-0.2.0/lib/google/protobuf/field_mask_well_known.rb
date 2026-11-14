# frozen_string_literal: true

Google::Protobuf::FieldMask.class_eval do
  def self.decode_json_hash(json, registry:, ignore_unknown_fields: false)
    raise DecodeError, "expected string for #{full_name}, got #{json.inspect}" unless json.is_a? String

    paths = json.split(",").each do |field|
      unless /\A[a-zA-Z]+\z/.match?(field)
        raise Protobug::DecodeError,
              "field mask has invalid characters from JSON: #{field.inspect}"
      end

      field.gsub!(/(?<!\A)([A-Z])/) do |m|
        "_#{m.downcase}"
      end
    end
    json = { "paths" => paths }
    super
  end

  def as_json(print_unknown_fields: false)
    _ = print_unknown_fields

    paths.map do |path|
      unless /\A[a-z]+(_[a-z]+)*\z/.match?(path)
        raise Protobug::EncodeError,
              "cannot encode field mask paths to JSON with non-lowercase-alpha characters: #{path.inspect}"
      end

      path.gsub(/(?<!\A)(?:_([a-z]+))/, &:capitalize)
    end.join(",")
  end
end
