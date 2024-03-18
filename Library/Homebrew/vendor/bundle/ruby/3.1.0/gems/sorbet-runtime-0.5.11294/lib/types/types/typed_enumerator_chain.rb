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

    def new(*args, &blk)
      T.unsafe(Enumerator::Chain).new(*args, &blk)
    end

    class Untyped < TypedEnumeratorChain
      def initialize
        super(T.untyped)
      end

      def valid?(obj)
        obj.is_a?(Enumerator::Chain)
      end
    end
  end
end
