# typed: strict
# frozen_string_literal: true

require "fiddle"

module OS
  module Mac
    # Wrapping module for FFI calls to system libraries.
    module FFI
      sig { returns(Fiddle::Handle) }
      private_class_method def self.libsystem
        @libsystem ||= T.let(Fiddle.dlopen("/usr/lib/libSystem.B.dylib"), T.nilable(Fiddle::Handle))
      end

      sig { params(path: String).returns(T::Boolean) }
      def self.dyld_shared_cache_contains_path(path)
        @dyld_shared_cache_contains_path ||= T.let(
          Fiddle::Function.new(
            libsystem["_dyld_shared_cache_contains_path"],
            [Fiddle::TYPE_CONST_STRING],
            Fiddle::TYPE_BOOL,
          ), T.nilable(Fiddle::Function)
        )
        @dyld_shared_cache_contains_path.call(path)
      end
    end
  end
end
