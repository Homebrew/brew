# typed: strict
# frozen_string_literal: true

require "os/mac/ffi/native_library"

module OS
  module Mac
    module FFI
      module ObjectiveC
        extend NativeLibrary

        use_library "/usr/lib/libobjc.A.dylib"

        sig { params(name: String).returns(Fiddle::Pointer) }
        def self.class_get(name)
          function("objc_getClass", [Fiddle::TYPE_CONST_STRING], Fiddle::TYPE_VOIDP).call(name)
        end

        sig { params(name: String).returns(Fiddle::Pointer) }
        def self.selector(name)
          function("sel_registerName", [Fiddle::TYPE_CONST_STRING], Fiddle::TYPE_VOIDP).call(name)
        end

        sig {
          params(
            receiver:       Fiddle::Pointer,
            selector_name:  String,
            argument_types: T::Array[Integer],
            return_type:    Integer,
            arguments:      T.untyped,
          ).returns(T.untyped)
        }
        def self.message_send(receiver, selector_name, argument_types, return_type, *arguments)
          function("objc_msgSend", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, *argument_types], return_type)
            .call(receiver, selector(selector_name), *arguments)
        end
      end
    end
  end
end
