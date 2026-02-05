# typed: strict
# frozen_string_literal: true

require "os/mac/mach"

module MachOPathname
  module ClassMethods
    sig { params(path: T.any(Pathname, String, MachOShim)).returns(MachOShim) }
    def wrap(path)
      return path if path.is_a?(MachOShim)

      path = ::Pathname.new(path)
      path.extend(MachOShim)
      T.cast(path, MachOShim)
    end
  end

  extend ClassMethods
end

BinaryPathname.singleton_class.prepend(MachOPathname::ClassMethods)

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

Pathname.singleton_class.prepend(OS::Mac::Pathname::ClassMethods)
