# frozen_string_literal: true
# typed: true

module T::Types
  # Since we do type erasure at runtime, this just validates the variance and
  # provides some syntax for the static type checker
  class TypeVariable < Base
    attr_reader :variance

    VALID_VARIANCES = %i[in out invariant].freeze

    def initialize(variance)
      case variance
      when Hash
        raise ArgumentError.new("Pass bounds using a block. Got: #{variance}")
        T.absurd(variance)
      when *VALID_VARIANCES then nil
      else
        raise TypeError.new("invalid variance #{variance}")
      end
      @variance = variance
    end

    def build_type
      nil
    end

    # overrides Base
    def build_lazy_fields
      nil
    end

    def valid?(obj)
      true
    end

    def subtype_of_single?(type)
      true
    end

    def name
      Untyped.new.name
    end
  end
end
