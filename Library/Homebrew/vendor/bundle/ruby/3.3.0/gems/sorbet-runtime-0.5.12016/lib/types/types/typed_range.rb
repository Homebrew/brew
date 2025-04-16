# frozen_string_literal: true
# typed: true

module T::Types
  class TypedRange < TypedEnumerable
    def underlying_class
      Range
    end

    # overrides Base
    def name
      "T::Range[#{type.name}]"
    end

    # overrides Base
    def recursively_valid?(obj)
      obj.is_a?(Range) && super
    end

    # overrides Base
    def valid?(obj)
      obj.is_a?(Range)
    end

    def new(*args)
      T.unsafe(Range).new(*args)
    end
  end
end
