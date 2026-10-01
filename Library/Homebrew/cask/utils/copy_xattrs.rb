# typed: strict
# frozen_string_literal: true

require "standalone"
require "os/mac/ffi"

OS::Mac::FFI.copy_xattrs(ARGV.fetch(0), ARGV.fetch(1))
