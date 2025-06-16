# typed: strict
# frozen_string_literal: true

require "socket"

module OS
  module Mac
    # Wrapper around UNIXSocket to allow > 104 characters on macOS.
    module UNIXSocketExt
      extend T::Helpers

      requires_ancestor { Kernel }

      sig { params(path: String).returns(String) }
      def sockaddr_un(path)
        if path.bytesize > 252 # largest size that can fit into a single-byte length
          raise ArgumentError, "too long unix socket path (#{path.bytesize} bytes given but 252 bytes max)"
        end

        [
          path.bytesize + 3, # = length (1 byte) + family (1 byte) + path (variable) + null terminator (1 byte)
          1, # AF_UNIX
          path,
        ].pack("CCZ*")
      end
    end
  end
end

Utils::UNIXSocketExt.singleton_class.prepend(OS::Mac::UNIXSocketExt)
