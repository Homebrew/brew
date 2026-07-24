# frozen_string_literal: true
# typed: true

module T::Types
  # Takes a list of types. Validates that an object matches all of the types.
  class Intersection < Base
    def initialize(types)
      @inner_types = types
    end

    def types
      @types ||= @inner_types.flat_map do |type|
        type = T::Utils.resolve_alias(type)
        if type.is_a?(Intersection)
          # Simplify nested intersections (mostly so `name` returns a nicer value)
          type.types
        else
          T::Utils.coerce(type)
        end
      end.uniq
    end

    def build_type
      types
      nil
    end

    # overrides Base
    def name
      "T.all(#{types.map(&:name).compact.sort.join(', ')})"
    end

    # overrides Base
    def recursively_valid?(obj)
      members = types
      index = 0
      while index < members.length
        return false unless members.fetch(index).recursively_valid?(obj)
        index += 1
      end
      true
    end

    # overrides Base
    def valid?(obj)
      members = types
      index = 0
      while index < members.length
        return false unless members.fetch(index).valid?(obj)
        index += 1
      end
      true
    end

    # overrides Base
    private def subtype_of_single?(other)
      raise "This should never be reached if you're going through `subtype_of?` (and you should be)"
    end

  end
end
