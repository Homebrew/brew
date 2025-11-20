# typed: strict
# frozen_string_literal: true

if OS.mac?
  require "os/mac/mach"
  module BinaryPathname; include MachOShim; end
  require "extend/os/mac/extend/pathname"
elsif OS.linux?
  require "os/linux/elf"
  module BinaryPathname; include ELFShim; end
  require "extend/os/linux/extend/pathname"
end
