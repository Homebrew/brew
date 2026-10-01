# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module Pathname
      module ClassMethods
        extend T::Helpers

        requires_ancestor { T.class_of(::Pathname) }

        sig { void }
        def activate_extensions!
          super

          prepend(MachOShim)
        end
      end
    end
  end
end
