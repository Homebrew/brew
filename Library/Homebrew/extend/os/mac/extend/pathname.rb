# typed: strict
# frozen_string_literal: true

require "os/mac/mach"

module MachOPathname
  module ClassMethods
    sig { params(path: T.any(Pathname, String, MachOShim)).returns(MachOShim) }
    def wrap(path)
      Kernel.require "macho"
      return path if path.is_a?(MachOShim)

      path = ::Pathname.new(path)
      path.extend(MachOShim)
      T.cast(path, MachOShim)
    end
  end

  extend ClassMethods
end

BinaryPathname.singleton_class.prepend(MachOPathname::ClassMethods)
require "extend/os/mac/extend/pathname/os"

Pathname.singleton_class.prepend(OS::Mac::Pathname::ClassMethods)
