# frozen_string_literal: true
# typed: true

module T::Types
  # Modeling AttachedClass properly at runtime would require additional
  # tracking, so at runtime we permit all values and rely on the static checker.
  # As AttachedClass is modeled statically as a type member on every singleton
  # class, this is consistent with the runtime behavior for all type members.
  class AttachedClassType < Base

    def initialize(); end

    # overrides Base
    def name
      "T.attached_class"
    end

    # overrides Base
    def valid?(obj)
      true
    end

    # overrides Base
    private def subtype_of_single?(other)
      case other
      when AttachedClassType
        true
      else
        false
      end
    end

    module Private
      INSTANCE = AttachedClassType.new.freeze
    end
  end
end
