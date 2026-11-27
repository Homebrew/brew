# typed: strict
# frozen_string_literal: true

require_relative "../../standalone"
require "os/mac/ffi/xattr"

OS::Mac::FFI.copy_xattrs(ARGV.fetch(0), ARGV.fetch(1))
