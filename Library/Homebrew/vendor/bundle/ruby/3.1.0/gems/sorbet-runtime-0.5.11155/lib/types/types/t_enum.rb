# frozen_string_literal: true
# typed: true

module T::Types
  # Validates that an object is equal to another T::Enum singleton value.
  class TEnum < Base
    attr_reader :val

    def initialize(val)
      @val = val
    end

    # overrides Base
    def name
      # Strips the #<...> off, just leaving the ...
      # Reasoning: the user will have written something like
      #   T.any(MyEnum::A, MyEnum::B)
      # in the type, so we should print what they wrote in errors, not:
      #   T.any(#<MyEnum::A>, #<MyEnum::B>)
      @val.inspect[2..-2]
    end

    # overrides Base
    def valid?(obj)
      @val == obj
    end

    # overrides Base
    private def subtype_of_single?(other)
      case other
      when TEnum
        @val == other.val
      else
        false
      end
    end
  end
end
