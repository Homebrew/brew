# frozen_string_literal: true

Google::Protobuf.module_eval do
  %i[DoubleValue FloatValue
     Int64Value UInt64Value
     Int32Value UInt32Value
     BoolValue
     StringValue BytesValue]
    .each do |const|
    klass = const_get(const)
    klass.class_eval do
      def self.decode_json_hash(json, registry:, ignore_unknown_fields: false)
        return Protobug::UNSET if json.nil?

        json = { "value" => json }
        super
      end

      def as_json(print_unknown_fields: false)
        field = self.class.fields_by_name.fetch("value")
        field.send(:json_encode_one, value, print_unknown_fields: print_unknown_fields)
      end
    end
  end
end
