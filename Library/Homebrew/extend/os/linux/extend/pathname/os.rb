# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module Pathname
      module ClassMethods
        extend T::Helpers

        requires_ancestor { T.class_of(::Pathname) }

        sig { void }
        def activate_extensions!
          super

          prepend(ELFShim)
        end
      end
    end
  end
end
