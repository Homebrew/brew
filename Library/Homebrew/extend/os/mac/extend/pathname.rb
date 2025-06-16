# typed: strict
# frozen_string_literal: true

require "os/mac/mach"

class Pathname
  prepend MachOShim
end
