# frozen_string_literal: true
# typed: true

module T::Types
  class TypedArray < TypedEnumerable
    # overrides Base
    def name
      "T::Array[#{type.name}]"
    end

    def underlying_class
      Array
    end

    # overrides Base
    def recursively_valid?(obj)
      obj.is_a?(Array) && super
    end

    # overrides Base
    def valid?(obj)
      obj.is_a?(Array)
    end

    def new(*args)
      Array.new(*T.unsafe(args))
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

          type = TypedArray.new(mod)

          if CACHE_FROZEN_OBJECTS || (!mod.frozen? && !type.frozen?)
            @cache[mod] = type
          end
          type
        end
      end
    end

    class Untyped < TypedArray
      def initialize
        super(T::Types::Untyped::Private::INSTANCE)
      end

      def valid?(obj)
        obj.is_a?(Array)
      end

      def freeze
        build_type # force lazy initialization before freezing the object
        super
      end

      module Private
        INSTANCE = Untyped.new.freeze
      end
    end
  end
end
