# typed: strict
# frozen_string_literal: true

require "os/linux/elf"

class Pathname
  prepend ELFShim
end
