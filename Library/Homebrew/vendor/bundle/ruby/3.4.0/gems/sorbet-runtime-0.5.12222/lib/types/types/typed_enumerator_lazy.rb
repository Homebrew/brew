# frozen_string_literal: true
# typed: true

module T::Types
  class TypedEnumeratorLazy < TypedEnumerable
    def underlying_class
      Enumerator::Lazy
    end

    # overrides Base
    def name
      "T::Enumerator::Lazy[#{type.name}]"
    end

    # overrides Base
    def recursively_valid?(obj)
      obj.is_a?(Enumerator::Lazy) && super
    end

    # overrides Base
    def valid?(obj)
      obj.is_a?(Enumerator::Lazy)
    end

    def new(*args, &blk)
      T.unsafe(Enumerator::Lazy).new(*args, &blk)
    end

    class Untyped < TypedEnumeratorLazy
      def initialize
        super(T::Types::Untyped::Private::INSTANCE)
      end

      def valid?(obj)
        obj.is_a?(Enumerator::Lazy)
      end
    end
  end
end
