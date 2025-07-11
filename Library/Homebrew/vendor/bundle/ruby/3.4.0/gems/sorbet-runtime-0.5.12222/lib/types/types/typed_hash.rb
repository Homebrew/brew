# frozen_string_literal: true
# typed: true

module T::Types
  class TypedHash < TypedEnumerable
    def underlying_class
      Hash
    end

    def initialize(keys:, values:)
      @inner_keys = keys
      @inner_values = values
    end

    # Technically we don't need this, but it is a nice api
    def keys
      @keys ||= T::Utils.coerce(@inner_keys)
    end

    # Technically we don't need this, but it is a nice api
    def values
      @values ||= T::Utils.coerce(@inner_values)
    end

    def type
      @type ||= T::Utils.coerce([keys, values])
    end

    # overrides Base
    def name
      "T::Hash[#{keys.name}, #{values.name}]"
    end

    # overrides Base
    def recursively_valid?(obj)
      obj.is_a?(Hash) && super
    end

    # overrides Base
    def valid?(obj)
      obj.is_a?(Hash)
    end

    def new(*args, &blk)
      Hash.new(*T.unsafe(args), &blk)
    end

    class Untyped < TypedHash
      def initialize
        super(keys: T.untyped, values: T.untyped)
      end

      def valid?(obj)
        obj.is_a?(Hash)
      end
    end
  end
end
