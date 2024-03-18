# frozen_string_literal: true
# typed: true

module T::Private::Types
  # Wraps a proc for a type alias to defer its evaluation.
  class TypeAlias < T::Types::Base

    def initialize(callable)
      @callable = callable
    end

    def build_type
      nil
    end

    def aliased_type
      @aliased_type ||= T::Utils.coerce(@callable.call)
    end

    # overrides Base
    def name
      aliased_type.name
    end

    # overrides Base
    def recursively_valid?(obj)
      aliased_type.recursively_valid?(obj)
    end

    # overrides Base
    def valid?(obj)
      aliased_type.valid?(obj)
    end
  end
end
