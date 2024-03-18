# frozen_string_literal: true
# typed: true

module T::Types
  class TypedSet < TypedEnumerable
    def underlying_class
      Hash
    end

    # overrides Base
    def name
      "T::Set[#{type.name}]"
    end

    # overrides Base
    def recursively_valid?(obj)
      # Re-implements non_forcing_is_a?
      return false if Object.autoload?(:Set) # Set is meant to be autoloaded but not yet loaded, this value can't be a Set
      return false unless Object.const_defined?(:Set) # Set is not loaded yet
      obj.is_a?(Set) && super
    end

    # overrides Base
    def valid?(obj)
      # Re-implements non_forcing_is_a?
      return false if Object.autoload?(:Set) # Set is meant to be autoloaded but not yet loaded, this value can't be a Set
      return false unless Object.const_defined?(:Set) # Set is not loaded yet
      obj.is_a?(Set)
    end

    def new(*args)
      # Fine for this to blow up, because hopefully if they're trying to make a
      # Set, they don't mind putting (or already have put) a `require 'set'` in
      # their program directly.
      Set.new(*T.unsafe(args))
    end

    class Untyped < TypedSet
      def initialize
        super(T.untyped)
      end

      def valid?(obj)
        # Re-implements non_forcing_is_a?
        return false if Object.autoload?(:Set) # Set is meant to be autoloaded but not yet loaded, this value can't be a Set
        return false unless Object.const_defined?(:Set) # Set is not loaded yet
        obj.is_a?(Set)
      end
    end
  end
end
