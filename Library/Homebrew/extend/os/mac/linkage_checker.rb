# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module LinkageChecker
      extend T::Helpers

      requires_ancestor { ::LinkageChecker }

      private

      sig { params(dylib: String).returns(T::Boolean) }
      def dylib_found_in_shared_cache?(dylib)
        return false if MacOS.version < :big_sur

        require "os/mac/ffi"
        MacOS::FFI.dyld_shared_cache_contains_path(dylib)
      end
    end
  end
end

LinkageChecker.prepend(OS::Mac::LinkageChecker)
