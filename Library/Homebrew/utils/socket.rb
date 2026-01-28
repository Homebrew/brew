# typed: strict
# frozen_string_literal: true

require "socket"

module Utils
  # Wrapper around UNIXSocket to allow > 104 characters on macOS.
  module UNIXSocketExt
    extend T::Generic

    sig {
      type_parameters(:U).params(
        path:   String,
        _block: T.proc.params(arg0: UNIXSocket).returns(T.type_parameter(:U)),
      ).returns(T.type_parameter(:U))
    }
    def self.open(path, &_block)
      socket = Socket.new(:UNIX, :STREAM)
      socket.connect(sockaddr_un(path))
      unix_socket = UNIXSocket.for_fd(socket.fileno)
      socket.autoclose = false # Transfer autoclose responsibility to UNIXSocket
      yield unix_socket
    end

    sig { params(path: String).returns(String) }
    def self.sockaddr_un(path)
      Socket.sockaddr_un(path)
    end
  end

  # Wrapper around UNIXServer to allow > 104 characters on macOS.
  class UNIXServerExt < Socket
    extend T::Generic

    Elem = type_member(:out) { { fixed: String } }

    sig { returns(String) }
    attr_reader :path

    sig { params(path: String).void }
    def initialize(path)
      super(:UNIX, :STREAM)
      bind(UNIXSocketExt.sockaddr_un(path))
      listen(Socket::SOMAXCONN)
      @path = path
    end

    sig { returns(UNIXSocket) }
    def accept_nonblock
      socket, = super
      socket.autoclose = false # Transfer autoclose responsibility to UNIXSocket
      UNIXSocket.for_fd(socket.fileno)
    end
  end
end

require "extend/os/utils/socket"
