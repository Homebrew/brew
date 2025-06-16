# frozen_string_literal: true
# typed: true

module T::Types
  class TypedEnumerator < TypedEnumerable
    def underlying_class
      Enumerator
    end

    # overrides Base
    def name
      "T::Enumerator[#{type.name}]"
    end

    # overrides Base
    def recursively_valid?(obj)
      obj.is_a?(Enumerator) && super
    end

    # overrides Base
    def valid?(obj)
      obj.is_a?(Enumerator)
    end

    def new(*args, &blk)
      T.unsafe(Enumerator).new(*args, &blk)
    end

    class Untyped < TypedEnumerator
      def initialize
        super(T::Types::Untyped::Private::INSTANCE)
      end

      def valid?(obj)
        obj.is_a?(Enumerator)
      end
    end
  end
end
