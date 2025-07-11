# frozen_string_literal: true
# typed: true

module T::Types
  # Validates that an object belongs to the specified class.
  class Simple < Base
    NAME_METHOD = Module.instance_method(:name)
    private_constant(:NAME_METHOD)

    attr_reader :raw_type

    def initialize(raw_type)
      @raw_type = raw_type
    end

    def build_type
      nil
    end

    # overrides Base
    def name
      # Memoize to mitigate pathological performance with anonymous modules (https://bugs.ruby-lang.org/issues/11119)
      #
      # `name` isn't normally a hot path for types, but it is used in initializing a T::Types::Union,
      # and so in `T.nilable`, and so in runtime constructions like `x = T.let(nil, T.nilable(Integer))`.
      #
      # Care more about back compat than we do about performance here.
      # Once 2.6 is well in the rear view mirror, we can replace this.
      # rubocop:disable Performance/BindCall
      @name ||= (NAME_METHOD.bind(@raw_type).call || @raw_type.name).freeze
      # rubocop:enable Performance/BindCall
    end

    # overrides Base
    def valid?(obj)
      obj.is_a?(@raw_type)
    end

    # overrides Base
    private def subtype_of_single?(other)
      case other
      when Simple
        @raw_type <= other.raw_type
      when TypedClass
        # This case is a bit odd--we would have liked to solve this like we do
        # for `T::Array` et al., but don't for backwards compatibility.
        # See `type_for_module` below.
        @raw_type <= other.underlying_class
      else
        false
      end
    end

    # overrides Base
    private def error_message(obj)
      error_message = super(obj)
      actual_name = obj.class.name

      return error_message unless name == actual_name

      <<~MSG.strip
        #{error_message}

        The expected type and received object type have the same name but refer to different constants.
        Expected type is #{name} with object id #{@raw_type.__id__}, but received type is #{actual_name} with object id #{obj.class.__id__}.

        There might be a constant reloading problem in your application.
      MSG
    end

    def to_nilable
      @nilable ||= T::Private::Types::SimplePairUnion.new(
        self,
        T::Utils::Nilable::NIL_TYPE,
      )
    end

    module Private
      module Pool
        CACHE_FROZEN_OBJECTS = begin
          ObjectSpace::WeakMap.new[1] = 1
          true # Ruby 2.7 and newer
                               rescue ArgumentError # Ruby 2.6 and older
                                 false
        end

        @cache = ObjectSpace::WeakMap.new

        def self.type_for_module(mod)
          cached = @cache[mod]
          return cached if cached

          type = if mod == ::Array
            T::Array[T.untyped]
          elsif mod == ::Hash
            T::Hash[T.untyped, T.untyped]
          elsif mod == ::Enumerable
            T::Enumerable[T.untyped]
          elsif mod == ::Enumerator
            T::Enumerator[T.untyped]
          elsif mod == ::Range
            T::Range[T.untyped]
          elsif !Object.autoload?(:Set) && Object.const_defined?(:Set) && mod == ::Set
            T::Set[T.untyped]
          else
            # ideally we would have a case mapping from ::Class -> T::Class here
            # but for backwards compatibility we don't have that, and instead
            # have a special case in subtype_of_single?
            Simple.new(mod)
          end

          # Unfortunately, we still need to check if the module is frozen,
          # since on 2.6 and older WeakMap adds a finalizer to the key that is added
          # to the map, so that it can clear the map entry when the key is
          # garbage collected.
          # For a frozen object, though, adding a finalizer is not a valid
          # operation, so this still raises if `mod` is frozen.
          if CACHE_FROZEN_OBJECTS || (!mod.frozen? && !type.frozen?)
            @cache[mod] = type
          end
          type
        end
      end
    end
  end
end
