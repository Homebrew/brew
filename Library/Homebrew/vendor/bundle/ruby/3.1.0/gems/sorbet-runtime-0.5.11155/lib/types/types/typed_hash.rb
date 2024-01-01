# frozen_string_literal: true
# typed: true

module T::Types
  class TypedHash < TypedEnumerable
    # Technically we don't need these, but they are a nice api
    attr_reader :keys, :values

    def underlying_class
      Hash
    end

    def initialize(keys:, values:)
      @keys = T::Utils.coerce(keys)
      @values = T::Utils.coerce(values)
      @type = T::Utils.coerce([keys, values])
    end

    # overrides Base
    def name
      "T::Hash[#{@keys.name}, #{@values.name}]"
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
