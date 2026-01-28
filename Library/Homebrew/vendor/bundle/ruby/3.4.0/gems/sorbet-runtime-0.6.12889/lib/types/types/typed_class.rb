# frozen_string_literal: true
# typed: true

module T::Types
  class TypedClass < T::Types::Base
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

    # overrides Base
    def name
      "T::Class[#{type.name}]"
    end

    def underlying_class
      Class
    end

    # overrides Base
    def valid?(obj)
      Class.===(obj)
    end

    # overrides Base
    private def subtype_of_single?(type)
      case type
      when TypedClass, TypedModule
        # treat like generics are erased
        true
      when Simple
        Class <= type.raw_type
      else
        false
      end
    end

    module Private
      module Pool
        CACHE_FROZEN_OBJECTS =
          begin
            ObjectSpace::WeakMap.new[1] = 1
            true # Ruby 2.7 and newer
          rescue ArgumentError
            false # Ruby 2.6 and older
          end

        @cache = ObjectSpace::WeakMap.new

        def self.type_for_module(mod)
          cached = @cache[mod]
          return cached if cached

          type = TypedClass.new(mod)

          if CACHE_FROZEN_OBJECTS || (!mod.frozen? && !type.frozen?)
            @cache[mod] = type
          end
          type
        end
      end
    end

    class Untyped < TypedClass
      def initialize
        super(T::Types::Untyped::Private::INSTANCE)
      end

      def freeze
        build_type # force lazy initialization before freezing the object
        super
      end

      module Private
        INSTANCE = Untyped.new.freeze
      end
    end

    class Anything < TypedClass
      def initialize
        super(T.anything)
      end

      def freeze
        build_type # force lazy initialization before freezing the object
        super
      end

      module Private
        INSTANCE = Anything.new.freeze
      end
    end
  end
end
