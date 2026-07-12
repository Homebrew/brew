# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    # Wrapping module for FFI calls to system libraries.
    module FFI
    end
  end
end

require "os/mac/ffi/native_library"
require "os/mac/ffi/dyld"
require "os/mac/ffi/xattr"
require "os/mac/ffi/objective_c"
require "os/mac/ffi/core_foundation"
require "os/mac/ffi/foundation"
require "os/mac/ffi/launch_services"
require "os/mac/ffi/security"
