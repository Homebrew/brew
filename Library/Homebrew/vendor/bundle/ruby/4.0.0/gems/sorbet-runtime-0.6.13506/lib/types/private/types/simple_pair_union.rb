# frozen_string_literal: true
# typed: true

# Specialization of Union for the common case of the union of two simple types.
#
# This covers e.g. T.nilable(SomeModule), T.any(Integer, Float), and T::Boolean.
class T::Private::Types::SimplePairUnion < T::Types::Union
  class DuplicateType < RuntimeError; end

  # @param type_a [T::Types::Simple]
  # @param type_b [T::Types::Simple]
  def initialize(type_a, type_b)
    if type_a == type_b
      raise DuplicateType.new("#{type_a} == #{type_b}")
    end

    @raw_a = type_a.raw_type
    @raw_b = type_b.raw_type
  end

  # @override Union
  def recursively_valid?(obj)
    obj.is_a?(@raw_a) || obj.is_a?(@raw_b)
  end

  # @override Union
  def valid?(obj)
    obj.is_a?(@raw_a) || obj.is_a?(@raw_b)
  end

  # @override Union
  def types
    # We reconstruct the simple types rather than just storing them because
    # (1) this is normally not a hot path and (2) we want to keep the instance
    # variable count <= 3 so that we can fit in a 40 byte heap entry along
    # with object headers.
    @types ||= [
      T::Types::Simple::Private::Pool.type_for_module(@raw_a),
      T::Types::Simple::Private::Pool.type_for_module(@raw_b),
    ]
  end

  # overrides Union
  def unwrap_nilable
    a_nil = @raw_a.equal?(NilClass)
    b_nil = @raw_b.equal?(NilClass)
    if a_nil
      return types[1]
    end
    if b_nil
      return types[0]
    end
    nil
  end
end
