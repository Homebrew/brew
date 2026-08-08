# frozen_string_literal: true
# typed: true

module T::Types
  class TypedSet < TypedEnumerable
    # We can reference `Set` directly without a load guard: as of Ruby 3.2 it
    # ships as a default-autoloaded constant (Ruby registers `autoload :Set,
    # "set"`), so the first reference here transparently loads it. Ruby 3.3 --
    # the most recently supported release -- keeps this behavior, and Ruby 3.1
    # and earlier (which required an explicit `require "set"`) are past EOL.
    def underlying_class
      Set
    end

    # overrides Base
    def name
      "T::Set[#{type.name}]"
    end

    # overrides Base
    def recursively_valid?(obj)
      obj.is_a?(Set) && super
    end

    # overrides Base
    def valid?(obj)
      obj.is_a?(Set)
    end

    def new(...)
      Set.new(...)
    end

    class Untyped < TypedSet
      def initialize
        super(T::Types::Untyped::Private::INSTANCE)
      end

      def valid?(obj)
        obj.is_a?(Set)
      end
    end
  end
end
