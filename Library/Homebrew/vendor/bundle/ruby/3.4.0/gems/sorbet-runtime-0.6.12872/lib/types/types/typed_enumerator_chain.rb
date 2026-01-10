# frozen_string_literal: true
# typed: true

module T::Types
  class TypedEnumeratorChain < TypedEnumerable
    def underlying_class
      Enumerator::Chain
    end

    # overrides Base
    def name
      "T::Enumerator::Chain[#{type.name}]"
    end

    # overrides Base
    def recursively_valid?(obj)
      obj.is_a?(Enumerator::Chain) && super
    end

    # overrides Base
    def valid?(obj)
      obj.is_a?(Enumerator::Chain)
    end

    def new(...)
      Enumerator::Chain.new(...)
    end

    class Untyped < TypedEnumeratorChain
      def initialize
        super(T::Types::Untyped::Private::INSTANCE)
      end

      def valid?(obj)
        obj.is_a?(Enumerator::Chain)
      end
    end
  end
end
