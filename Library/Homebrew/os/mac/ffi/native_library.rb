# typed: strict
# frozen_string_literal: true

require "fiddle"

module OS
  module Mac
    module FFI
      # NativeLibrary provides helper methods for loading system libraries and accessing functions and constants.
      # Functions and constants are cached so they only need to be looked up once.
      module NativeLibrary
        private

        sig { params(path: String).void }
        def use_library(path)
          @library_path = T.let(path.freeze, T.nilable(String))
        end

        sig { returns(Fiddle::Handle) }
        def handle
          @handle ||= T.let(Fiddle.dlopen(T.must(@library_path)), T.nilable(Fiddle::Handle))
        end

        sig { params(name: String, argument_types: T::Array[Integer], return_type: Integer).returns(Fiddle::Function) }
        def function(name, argument_types, return_type)
          @functions ||= T.let({}, T.nilable(T::Hash[String, Fiddle::Function]))
          @functions["#{name}:#{argument_types.join(",")}:#{return_type}"] ||=
            Fiddle::Function.new(handle[name], argument_types, return_type)
        end

        sig { params(name: String, dereference: T::Boolean).returns(Fiddle::Pointer) }
        def constant(name, dereference: false)
          @constants ||= T.let({}, T.nilable(T::Hash[[String, T::Boolean], Fiddle::Pointer]))
          @constants[[name, dereference]] ||= begin
            pointer = Fiddle::Pointer.new(handle[name])
            dereference ? pointer.ptr : pointer
          end
        end
      end
    end
  end
end
