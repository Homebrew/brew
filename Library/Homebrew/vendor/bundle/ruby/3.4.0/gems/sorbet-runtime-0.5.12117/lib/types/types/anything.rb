# frozen_string_literal: true
# typed: true

module T::Types
  # The top type
  class Anything < Base
    def initialize; end

    def build_type
      nil
    end

    # overrides Base
    def name
      "T.anything"
    end

    # overrides Base
    def valid?(obj)
      true
    end

    # overrides Base
    private def subtype_of_single?(other)
      case other
      when T::Types::Anything then true
      else false
      end
    end

    module Private
      INSTANCE = Anything.new.freeze
    end
  end
end
