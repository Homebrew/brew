# frozen_string_literal: true

require "socket"

module Bundler
  class Settings
    # Class used to build the mirror set and then find a mirror for a given URI
    #
    # @param prober [Prober object, nil] by default a TCPSocketProbe, this object
    #   will be used to probe the mirror address to validate that the mirror replies.
    class Mirrors
      def initialize(prober = nil)
        @all = Mirror.new
        @prober = prober || TCPSocketProbe.new
        @mirrors = {}
      end

      # Returns a mirror for the given uri.
      #
      # Depending on the uri having a valid mirror or not, it may be a
      #   mirror that points to the provided uri
      def for(uri)
        if @all.validate!(@prober).valid?
          @all
        else
          fetch_valid_mirror_for(Settings.normalize_uri(uri))
        end
      end

      def each
        @mirrors.each do |k, v|
          yield k, v.uri.to_s
        end
      end

      def parse(key, value)
        config = MirrorConfig.new(key, value)
        mirror = if config.all?
          @all
        else
          @mirrors[config.uri] ||= Mirror.new
        end
        config.update_mirror(mirror)
      end

      private

      def fetch_valid_mirror_for(uri)
        downcased = uri.to_s.downcase
        mirror = @mirrors[downcased] || @mirrors[Gem::URI(downcased).host] || Mirror.new(uri)
        mirror.validate!(@prober)
        mirror = Mirror.new(uri) unless mirror.valid?
        mirror
      end
    end

    # A mirror
    #
    # Contains both the uri that should be used as a mirror and the
    #   fallback timeout which will be used for probing if the mirror
    #   replies on time or not.
    class Mirror
      DEFAULT_FALLBACK_TIMEOUT = 0.1

      attr_reader :uri, :fallback_timeout

      def initialize(uri = nil, fallback_timeout = 0)
        self.uri = uri
        self.fallback_timeout = fallback_timeout
        @valid = nil
      end

      def uri=(uri)
        @uri = if uri.nil?
          nil
        else
          Gem::URI(uri.to_s)
        end
        @valid = nil
      end

      def fallback_timeout=(timeout)
        case timeout
        when true, "true"
          @fallback_timeout = DEFAULT_FALLBACK_TIMEOUT
        when false, "false"
          @fallback_timeout = 0
        else
          @fallback_timeout = timeout.to_i
        end
        @valid = nil
      end

      def ==(other)
        !other.nil? && uri == other.uri && fallback_timeout == other.fallback_timeout
      end

      def valid?
        return false if @uri.nil?
        return @valid unless @valid.nil?
        false
      end

      def validate!(probe = nil)
        @valid = false if uri.nil?
        if @valid.nil?
          @valid = fallback_timeout == 0 || (probe || TCPSocketProbe.new).replies?(self)
        end
        self
      end
    end

    # Class used to parse one configuration line
    #
    # Gets the configuration line and the value.
    #   This object provides a `update_mirror` method
    #   used to setup the given mirror value.
    class MirrorConfig
      attr_accessor :uri, :value

      def initialize(config_line, value)
        uri, fallback =
          config_line.match(%r{\Amirror\.(all|.+?)(\.fallback_timeout)?\/?\z}).captures
        @fallback = !fallback.nil?
        @all = false
        if uri == "all"
          @all = true
        else
          @uri = Gem::URI(uri).absolute? ? Settings.normalize_uri(uri) : uri
        end
        @value = value
      end

      def all?
        @all
      end

      def update_mirror(mirror)
        if @fallback
          mirror.fallback_timeout = @value
        else
          mirror.uri = Settings.normalize_uri(@value)
        end
      end
    end

    # Class used for probing TCP availability for a given mirror.
    class TCPSocketProbe
      def replies?(mirror)
        MirrorSockets.new(mirror).any? do |socket, address, timeout|
          socket.connect_nonblock(address)
        rescue Errno::EINPROGRESS
          wait_for_writtable_socket(socket, address, timeout)
        rescue RuntimeError # Connection failed somehow, again
          false
        end
      end

      private

      def wait_for_writtable_socket(socket, address, timeout)
        if IO.select(nil, [socket], nil, timeout)
          probe_writtable_socket(socket, address)
        else # TCP Handshake timed out, or there is something dropping packets
          false
        end
      end

      def probe_writtable_socket(socket, address)
        socket.connect_nonblock(address)
      rescue Errno::EISCONN
        true
      rescue StandardError # Connection failed
        false
      end
    end
  end

  # Class used to build the list of sockets that correspond to
  #   a given mirror.
  #
  # One mirror may correspond to many different addresses, both
  #   because of it having many dns entries or because
  #   the network interface is both ipv4 and ipv5
  class MirrorSockets
    def initialize(mirror)
      @timeout = mirror.fallback_timeout
      @addresses = Socket.getaddrinfo(mirror.uri.host, mirror.uri.port).map do |address|
        SocketAddress.new(address[0], address[3], address[1])
      end
    end

    def any?
      @addresses.any? do |address|
        socket = Socket.new(Socket.const_get(address.type), Socket::SOCK_STREAM, 0)
        socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
        value = yield socket, address.to_socket_address, @timeout
        socket.close unless socket.closed?
        value
      end
    end
  end

  # Socket address builder.
  #
  # Given a socket type, a host and a port,
  #   provides a method to build sockaddr string
  class SocketAddress
    attr_reader :type, :host, :port

    def initialize(type, host, port)
      @type = type
      @host = host
      @port = port
    end

    def to_socket_address
      Socket.pack_sockaddr_in(@port, @host)
    end
  end
end
