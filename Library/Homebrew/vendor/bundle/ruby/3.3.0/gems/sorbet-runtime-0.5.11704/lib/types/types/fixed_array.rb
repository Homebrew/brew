# frozen_string_literal: true
# https://jira.corp.stripe.com/browse/RUBYPLAT-1107
# typed: false

module T::Types
  # Takes a list of types. Validates each item in an array using the type in the same position
  # in the list.
  class FixedArray < Base
    def initialize(types)
      @inner_types = types
    end

    def types
      @types ||= @inner_types.map {|type| T::Utils.coerce(type)}
    end

    def build_type
      types
      nil
    end

    # overrides Base
    def name
      "[#{types.join(', ')}]"
    end

    # overrides Base
    def recursively_valid?(obj)
      if obj.is_a?(Array) && obj.length == types.length
        i = 0
        while i < types.length
          if !types[i].recursively_valid?(obj[i])
            return false
          end
          i += 1
        end
        true
      else
        false
      end
    end

    # overrides Base
    def valid?(obj)
      if obj.is_a?(Array) && obj.length == types.length
        i = 0
        while i < types.length
          if !types[i].valid?(obj[i])
            return false
          end
          i += 1
        end
        true
      else
        false
      end
    end

    # overrides Base
    private def subtype_of_single?(other)
      case other
      when FixedArray
        # Properly speaking, covariance here is unsound since arrays
        # can be mutated, but sorbet implements covariant tuples for
        # ease of adoption.
        types.size == other.types.size && types.zip(other.types).all? do |t1, t2|
          t1.subtype_of?(t2)
        end
      when TypedArray
        # warning: covariant arrays

        value1, value2, *values_rest = types
        value_type = if !value2.nil?
          T::Types::Union::Private::Pool.union_of_types(value1, value2, values_rest)
        elsif value1.nil?
          T.untyped
        else
          value1
        end

        T::Types::TypedArray.new(value_type).subtype_of?(other)
      else
        false
      end
    end

    # This gives us better errors, e.g.:
    # "Expected [String, Symbol], got [String, String]"
    # instead of
    # "Expected [String, Symbol], got Array".
    #
    # overrides Base
    def describe_obj(obj)
      if obj.is_a?(Array)
        if obj.length == types.length
          item_classes = obj.map(&:class).join(', ')
          "type [#{item_classes}]"
        else
          "array of size #{obj.length}"
        end
      else
        super
      end
    end
  end
end
