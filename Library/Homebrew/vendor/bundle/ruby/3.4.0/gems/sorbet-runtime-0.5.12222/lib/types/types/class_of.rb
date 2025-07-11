# frozen_string_literal: true
# typed: true

module T::Types
  # Validates that an object belongs to the specified class.
  class ClassOf < Base
    attr_reader :type

    def initialize(type)
      @type = type
    end

    def build_type
      nil
    end

    # overrides Base
    def name
      "T.class_of(#{@type})"
    end

    # overrides Base
    def valid?(obj)
      obj.is_a?(@type.singleton_class)
    end

    # overrides Base
    def subtype_of_single?(other)
      case other
      when ClassOf
        @type.is_a?(other.type.singleton_class)
      when Simple
        @type.is_a?(other.raw_type)
      when TypedClass
        @type.is_a?(other.underlying_class)
      else
        false
      end
    end

    # overrides Base
    def describe_obj(obj)
      obj.inspect
    end

    # So that `T.class_of(...)[...]` syntax is valid.
    # Mirrors the definition of T::Generic#[] (generics are erased).
    #
    # We avoid simply writing `include T::Generic` because we don't want any of
    # the other methods to appear (`T.class_of(A).type_member` doesn't make sense)
    def [](*types)
      self
    end
  end
end
