# typed: strict

# The classes below are reopened in `standalone/sorbet.rb` to override `valid?`.
# We define their `build_type` method here to make the type checker happy, and
# to avoid replacing the original definitions of the method.
module T
  module Types
    class FixedArray < Base
      sig { override.void }
      def build_type; end
    end

    class FixedHash < Base
      sig { override.void }
      def build_type; end
    end

    class Intersection < Base
      sig { override.void }
      def build_type; end
    end

    class TypedEnumerable < Base
      sig { override.void }
      def build_type; end
    end

    class TypedArray < TypedEnumerable
      sig { override.void }
      def build_type; end
    end

    class TypedEnumeratorChain < TypedEnumerable
      sig { override.void }
      def build_type; end
    end

    class TypedEnumeratorLazy < TypedEnumerable
      sig { override.void }
      def build_type; end
    end

    class TypedHash < TypedEnumerable
      sig { override.void }
      def build_type; end
    end

    class TypedRange < TypedEnumerable
      sig { override.void }
      def build_type; end
    end

    class TypedSet < TypedEnumerable
      sig { override.void }
      def build_type; end
    end

    class Union < Base
      sig { override.void }
      def build_type; end
    end
  end
end
