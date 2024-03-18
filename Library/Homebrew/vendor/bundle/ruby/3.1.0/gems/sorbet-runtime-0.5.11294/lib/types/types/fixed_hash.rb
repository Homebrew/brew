# frozen_string_literal: true
# typed: true

module T::Types
  # Takes a hash of types. Validates each item in a hash using the type in the same position
  # in the list.
  class FixedHash < Base
    def initialize(types)
      @inner_types = types
    end

    def types
      @types ||= @inner_types.transform_values {|v| T::Utils.coerce(v)}
    end

    def build_type
      types
      nil
    end

    # overrides Base
    def name
      serialize_hash(types)
    end

    # overrides Base
    def recursively_valid?(obj)
      return false unless obj.is_a?(Hash)
      return false if types.any? {|key, type| !type.recursively_valid?(obj[key])}
      return false if obj.any? {|key, _| !types[key]}
      true
    end

    # overrides Base
    def valid?(obj)
      return false unless obj.is_a?(Hash)
      return false if types.any? {|key, type| !type.valid?(obj[key])}
      return false if obj.any? {|key, _| !types[key]}
      true
    end

    # overrides Base
    private def subtype_of_single?(other)
      case other
      when FixedHash
        # Using `subtype_of?` here instead of == would be unsound
        types == other.types
      when TypedHash
        # warning: covariant hashes

        key1, key2, *keys_rest = types.keys.map {|key| T::Utils.coerce(key.class)}
        key_type = if !key2.nil?
          T::Types::Union::Private::Pool.union_of_types(key1, key2, keys_rest)
        elsif key1.nil?
          T.untyped
        else
          key1
        end

        value1, value2, *values_rest = types.values
        value_type = if !value2.nil?
          T::Types::Union::Private::Pool.union_of_types(value1, value2, values_rest)
        elsif value1.nil?
          T.untyped
        else
          value1
        end

        T::Types::TypedHash.new(keys: key_type, values: value_type).subtype_of?(other)
      else
        false
      end
    end

    # This gives us better errors, e.g.:
    # `Expected {a: String}, got {a: TrueClass}`
    # instead of
    # `Expected {a: String}, got Hash`.
    #
    # overrides Base
    def describe_obj(obj)
      if obj.is_a?(Hash)
        "type #{serialize_hash(obj.transform_values(&:class))}"
      else
        super
      end
    end

    private

    def serialize_hash(hash)
      entries = hash.map do |(k, v)|
        if Symbol === k && ":#{k}" == k.inspect
          "#{k}: #{v}"
        else
          "#{k.inspect} => #{v}"
        end
      end

      "{#{entries.join(', ')}}"
    end
  end
end
