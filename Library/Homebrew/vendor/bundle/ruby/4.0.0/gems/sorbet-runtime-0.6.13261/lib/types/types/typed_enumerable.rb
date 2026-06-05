# frozen_string_literal: true
# typed: true

module T::Types
  # Note: All subclasses of Enumerable should add themselves to the
  # `case` statement below in `describe_obj` in order to get better
  # error messages.
  class TypedEnumerable < Base
    def initialize(type)
      @inner_type = type
    end

    def type
      @type ||= T::Utils.coerce(@inner_type)
    end

    def build_type
      type
      nil
    end

    def underlying_class
      Enumerable
    end

    # overrides Base
    def name
      "T::Enumerable[#{type.name}]"
    end

    # overrides Base
    def valid?(obj)
      obj.is_a?(Enumerable)
    end

    # overrides Base
    def recursively_valid?(obj)
      return false unless obj.is_a?(Enumerable)
      case obj
      when Array
        it = 0
        while it < obj.count
          return false unless type.recursively_valid?(obj[it])
          it += 1
        end
        true
      when Hash
        type_ = self.type
        return false unless type_.is_a?(FixedArray)
        key_type, value_type = type_.types
        return false if key_type.nil? || value_type.nil? || type_.types.size > 2
        obj.each_pair do |key, val|
          # Some objects (I'm looking at you Rack::Utils::HeaderHash) don't
          # iterate over a [key, value] array, so we can't just use the type.recursively_valid?(v)
          return false if !key_type.recursively_valid?(key) || !value_type.recursively_valid?(val)
        end
        true
      when Enumerator::Lazy
        # Enumerators can be unbounded: see `[:foo, :bar].cycle`
        true
      when Enumerator::Chain
        # Enumerators can be unbounded: see `[:foo, :bar].cycle`
        true
      when Enumerator
        # Enumerators can be unbounded: see `[:foo, :bar].cycle`
        true
      when Range
        # A nil beginning or a nil end does not provide any type information. That is, nil in a range represents
        # boundlessness, it does not express a type. For example `(nil...nil)` is not a T::Range[NilClass], its a range
        # of unknown types (T::Range[T.untyped]).
        # Similarly, `(nil...1)` is not a `T::Range[T.nilable(Integer)]`, it's a boundless range of Integer.
        (obj.begin.nil? || type.recursively_valid?(obj.begin)) && (obj.end.nil? || type.recursively_valid?(obj.end))
      when Set
        obj.each do |item|
          return false unless type.recursively_valid?(item)
        end

        true
      else
        # We don't check the enumerable since it isn't guaranteed to be
        # rewindable (e.g. STDIN) and it may be expensive to enumerate
        # (e.g. an enumerator that makes an HTTP request)"
        true
      end
    end

    # overrides Base
    private def subtype_of_single?(other)
      if other.class <= TypedEnumerable &&
         underlying_class <= other.underlying_class
        # Enumerables are covariant because they are read only
        #
        # Properly speaking, many Enumerable subtypes (e.g. Set)
        # should be invariant because they are mutable and support
        # both reading and writing. However, Sorbet treats *all*
        # Enumerable subclasses as covariant for ease of adoption.
        type.subtype_of?(other.type)
      elsif other.class <= Simple
        underlying_class <= other.raw_type
      else
        false
      end
    end

    # overrides Base
    def describe_obj(obj)
      return super unless obj.is_a?(Enumerable)
      type_from_instance(obj).name
    end

    private def type_from_instances(objs)
      return objs.class unless objs.is_a?(Enumerable)
      obtained_types = []
      begin
        objs.each do |x|
          obtained_types << type_from_instance(x)
        end
      rescue
        return T.untyped # all we can do is go with the types we have so far
      end
      if obtained_types.count > 1
        # Multiple kinds of bad types showed up, we'll suggest a union
        # type you might want.
        Union.new(obtained_types)
      elsif obtained_types.empty?
        T.noreturn
      else
        # Everything was the same bad type, lets just show that
        obtained_types.first
      end
    end

    private def type_from_instance(obj)
      if [true, false].include?(obj)
        return T::Boolean
      elsif !obj.is_a?(Enumerable)
        return obj.class
      end

      case obj
      when Array
        T::Array[type_from_instances(obj)]
      when Hash
        inferred_key = type_from_instances(obj.keys)
        inferred_val = type_from_instances(obj.values)
        T::Hash[inferred_key, inferred_val]
      when Range
        # We can't get any information from `NilClass` in ranges (since nil is used to represent boundlessness).
        typeable_objects = [obj.begin, obj.end].compact
        if typeable_objects.empty?
          T::Range[T.untyped]
        else
          T::Range[type_from_instances(typeable_objects)]
        end
      when Enumerator::Lazy
        T::Enumerator::Lazy[type_from_instances(obj)]
      when Enumerator::Chain
        T::Enumerator::Chain[type_from_instances(obj)]
      when Enumerator
        T::Enumerator[type_from_instances(obj)]
      when Set
        T::Set[type_from_instances(obj)]
      when IO
        # Short circuit for anything IO-like (File, etc.). In these cases,
        # enumerating the object is a destructive operation and might hang.
        obj.class
      else
        # This is a specialized enumerable type, just return the class.
        Object.instance_method(:class).bind_call(obj)
      end
    end

    class Untyped < TypedEnumerable
      def initialize
        super(T::Types::Untyped::Private::INSTANCE)
      end

      def valid?(obj)
        obj.is_a?(Enumerable)
      end
    end
  end
end
