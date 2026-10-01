# typed: strict
# frozen_string_literal: true

require "os/linux/elf"

module ELFPathname
  module ClassMethods
    sig { params(path: T.any(Pathname, String, ELFShim)).returns(ELFShim) }
    def wrap(path)
      return path if path.is_a?(ELFShim)

      path = ::Pathname.new(path)
      path.extend(ELFShim)
      T.cast(path, ELFShim)
    end
  end

  extend ClassMethods
end

BinaryPathname.singleton_class.prepend(ELFPathname::ClassMethods)
require "extend/os/linux/extend/pathname/os"

Pathname.singleton_class.prepend(OS::Linux::Pathname::ClassMethods)
