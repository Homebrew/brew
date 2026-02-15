# typed: strict
# frozen_string_literal: true

module OS
  module Mac
    module LinkageChecker
      private

      sig { returns(T::Boolean) }
      def system_libraries_exist_in_cache?
        # In macOS Big Sur and later, system libraries do not exist on-disk and instead exist in a cache.
        MacOS.version >= :big_sur
      end

      sig { params(dylib: String).returns(T::Boolean) }
      def dylib_found_in_shared_cache?(dylib)
        Kernel.require "fiddle"
        @dyld_shared_cache_contains_path ||= T.let(begin
          libc = Fiddle.dlopen("/usr/lib/libSystem.B.dylib")

          Fiddle::Function.new(
            libc["_dyld_shared_cache_contains_path"],
            [Fiddle::TYPE_CONST_STRING],
            Fiddle::TYPE_BOOL,
          )
        end, T.nilable(Fiddle::Function))

        @dyld_shared_cache_contains_path.call(dylib)
      end
    end
  end
end

LinkageChecker.prepend(OS::Mac::LinkageChecker)
