# typed: strict
# frozen_string_literal: true

require "os/mac/ffi/native_library"

module OS
  module Mac
    module FFI
      extend NativeLibrary

      use_library "/usr/lib/libSystem.B.dylib"

      # mach-o/dyld.h:
      #   bool _dyld_shared_cache_contains_path(const char* path);
      sig { params(path: String).returns(T::Boolean) }
      def self.dyld_shared_cache_contains_path(path)
        function(
          "_dyld_shared_cache_contains_path",
          [Fiddle::TYPE_CONST_STRING],
          Fiddle::TYPE_BOOL,
        ).call(path)
      end
    end
  end
end
