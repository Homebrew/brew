# typed: strict
# frozen_string_literal: true

require "os/mac/ffi/native_library"

module OS
  module Mac
    module FFI
      extend NativeLibrary

      use_library "/usr/lib/libSystem.B.dylib"

      sig { params(operation: String, path: String, attribute: T.nilable(String)).void }
      private_class_method def self.raise_xattr_error(operation, path, attribute = nil)
        raise SystemCallError.new("#{operation} for #{attribute || path}", Fiddle.last_error)
      end

      sig { params(path: String).returns(T::Array[String]) }
      def self.list_xattrs(path)
        names_length = function(
          "listxattr",
          [Fiddle::TYPE_CONST_STRING, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_INT],
          Fiddle::TYPE_SSIZE_T,
        ).call(path, nil, 0, 0)
        raise_xattr_error("listxattr", path) if names_length == -1
        return [] if names_length.zero?

        Fiddle::Pointer.malloc(names_length, Fiddle::RUBY_FREE) do |names|
          read_names_length = function(
            "listxattr",
            [Fiddle::TYPE_CONST_STRING, Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_INT],
            Fiddle::TYPE_SSIZE_T,
          ).call(path, names, names_length, 0)
          raise "Attributes changed during system call" if read_names_length != names_length

          names[0, read_names_length].split("\0")
        end
      end

      sig { params(path: String, attribute: String).returns(String) }
      def self.get_xattr(path, attribute)
        value_length = function(
          "getxattr",
          [
            Fiddle::TYPE_CONST_STRING, Fiddle::TYPE_CONST_STRING, Fiddle::TYPE_VOIDP,
            Fiddle::TYPE_SIZE_T, Fiddle::TYPE_UINT32_T, Fiddle::TYPE_INT
          ],
          Fiddle::TYPE_SSIZE_T,
        ).call(path, attribute, nil, 0, 0, 0)
        raise_xattr_error("getxattr", path, attribute) if value_length == -1
        return "" if value_length.zero?

        Fiddle::Pointer.malloc(value_length, Fiddle::RUBY_FREE) do |value|
          read_value_length = function(
            "getxattr",
            [
              Fiddle::TYPE_CONST_STRING, Fiddle::TYPE_CONST_STRING, Fiddle::TYPE_VOIDP,
              Fiddle::TYPE_SIZE_T, Fiddle::TYPE_UINT32_T, Fiddle::TYPE_INT
            ],
            Fiddle::TYPE_SSIZE_T,
          ).call(path, attribute, value, value_length, 0, 0)
          raise "Attributes changed during system call" if read_value_length != value_length

          value[0, read_value_length]
        end
      end

      sig { params(path: String, attribute: String, value: String).void }
      def self.set_xattr(path, attribute, value)
        result = function(
          "setxattr",
          [
            Fiddle::TYPE_CONST_STRING, Fiddle::TYPE_CONST_STRING, Fiddle::TYPE_VOIDP,
            Fiddle::TYPE_SIZE_T, Fiddle::TYPE_UINT32_T, Fiddle::TYPE_INT
          ],
          Fiddle::TYPE_INT,
        ).call(path, attribute, value.empty? ? nil : Fiddle::Pointer[value], value.bytesize, 0, 0)
        raise_xattr_error("setxattr", path, attribute) unless result.zero?
      end

      sig { params(path: String, attribute: String).void }
      def self.remove_xattr(path, attribute)
        result = function(
          "removexattr",
          [Fiddle::TYPE_CONST_STRING, Fiddle::TYPE_CONST_STRING, Fiddle::TYPE_INT],
          Fiddle::TYPE_INT,
        ).call(path, attribute, 0)
        raise_xattr_error("removexattr", path, attribute) unless result.zero?
      end

      sig { params(source: String, destination: String).void }
      def self.copy_xattrs(source, destination)
        list_xattrs(destination).each { |attribute| remove_xattr(destination, attribute) }
        list_xattrs(source).each { |attribute| set_xattr(destination, attribute, get_xattr(source, attribute)) }
      end
    end
  end
end
