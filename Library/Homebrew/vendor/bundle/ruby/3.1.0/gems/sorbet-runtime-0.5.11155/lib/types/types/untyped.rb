# frozen_string_literal: true
# typed: true

module T::Types
  # A dynamic type, which permits whatever
  class Untyped < Base

    def initialize; end

    # overrides Base
    def name
      "T.untyped"
    end

    # overrides Base
    def valid?(obj)
      true
    end

    # overrides Base
    private def subtype_of_single?(other)
      true
    end

    module Private
      INSTANCE = Untyped.new.freeze
    end
  end
end
