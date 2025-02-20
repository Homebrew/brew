# frozen_string_literal: true
# typed: true

# A marking class for when methods return void.
# Should never appear in types directly.
module T::Private::Types
  class Void < T::Types::Base
    ERROR_MESSAGE = "Validation is being done on an `Void`. Please report this bug at https://github.com/sorbet/sorbet/issues"

    # The actual return value of `.void` methods.
    #
    # Uses `module VOID` because this gives it a readable name when someone
    # examines it in Pry or with `#inspect` like:
    #
    #     T::Private::Types::Void::VOID
    #
    module VOID
      freeze
    end

    def build_type
      nil
    end

    # overrides Base
    def name
      "<VOID>"
    end

    # overrides Base
    def valid?(obj)
      raise ERROR_MESSAGE
    end

    # overrides Base
    private def subtype_of_single?(other)
      raise ERROR_MESSAGE
    end

    module Private
      INSTANCE = Void.new.freeze
    end
  end
end
