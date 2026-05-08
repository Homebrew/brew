# frozen_string_literal: true
# typed: true

module T::Types
  # The bottom type
  class NoReturn < Base
    def initialize; end

    def build_type
      nil
    end

    # overrides Base
    def name
      "T.noreturn"
    end

    # overrides Base
    def valid?(obj)
      false
    end

    # overrides Base
    private def subtype_of_single?(other)
      true
    end

    module Private
      INSTANCE = NoReturn.new.freeze
    end
  end
end
