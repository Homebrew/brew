# frozen_string_literal: true
=begin
= Info
  'OpenSSL for Ruby 2' project
  Copyright (C) 2001 GOTOU YUUZOU <gotoyuzo@notwork.org>
  All rights reserved.

= Licence
  This program is licensed under the same licence as Ruby.
  (See the file 'LICENCE'.)
=end

require "openssl/buffering"
require "io/nonblock"
require "ipaddr"
require "socket"

module OpenSSL
  module SSL
    class SSLContext
      DEFAULT_PARAMS = { # :nodoc:
        :min_version => OpenSSL::SSL::TLS1_VERSION,
        :verify_mode => OpenSSL::SSL::VERIFY_PEER,
        :verify_hostname => true,
        :options => -> {
          opts = OpenSSL::SSL::OP_ALL
          opts &= ~OpenSSL::SSL::OP_DONT_INSERT_EMPTY_FRAGMENTS
          opts |= OpenSSL::SSL::OP_NO_COMPRESSION
          opts
        }.call
      }

      if defined?(OpenSSL::PKey::DH)
        DEFAULT_2048 = OpenSSL::PKey::DH.new <<-_end_of_pem_
-----BEGIN DH PARAMETERS-----
MIIBCAKCAQEA7E6kBrYiyvmKAMzQ7i8WvwVk9Y/+f8S7sCTN712KkK3cqd1jhJDY
JbrYeNV3kUIKhPxWHhObHKpD1R84UpL+s2b55+iMd6GmL7OYmNIT/FccKhTcveab
VBmZT86BZKYyf45hUF9FOuUM9xPzuK3Vd8oJQvfYMCd7LPC0taAEljQLR4Edf8E6
YoaOffgTf5qxiwkjnlVZQc3whgnEt9FpVMvQ9eknyeGB5KHfayAc3+hUAvI3/Cr3
1bNveX5wInh5GDx1FGhKBZ+s1H+aedudCm7sCgRwv8lKWYGiHzObSma8A86KG+MD
7Lo5JquQ3DlBodj3IDyPrxIv96lvRPFtAwIBAg==
-----END DH PARAMETERS-----
        _end_of_pem_
        private_constant :DEFAULT_2048

        DEFAULT_TMP_DH_CALLBACK = lambda { |ctx, is_export, keylen| # :nodoc:
          warn "using default DH parameters." if $VERBOSE
          DEFAULT_2048
        }
      end

      if !(OpenSSL::OPENSSL_VERSION.start_with?("OpenSSL") &&
           OpenSSL::OPENSSL_VERSION_NUMBER >= 0x10100000)
        DEFAULT_PARAMS.merge!(
          ciphers: %w{
            ECDHE-ECDSA-AES128-GCM-SHA256
            ECDHE-RSA-AES128-GCM-SHA256
            ECDHE-ECDSA-AES256-GCM-SHA384
            ECDHE-RSA-AES256-GCM-SHA384
            DHE-RSA-AES128-GCM-SHA256
            DHE-DSS-AES128-GCM-SHA256
            DHE-RSA-AES256-GCM-SHA384
            DHE-DSS-AES256-GCM-SHA384
            ECDHE-ECDSA-AES128-SHA256
            ECDHE-RSA-AES128-SHA256
            ECDHE-ECDSA-AES128-SHA
            ECDHE-RSA-AES128-SHA
            ECDHE-ECDSA-AES256-SHA384
            ECDHE-RSA-AES256-SHA384
            ECDHE-ECDSA-AES256-SHA
            ECDHE-RSA-AES256-SHA
            DHE-RSA-AES128-SHA256
            DHE-RSA-AES256-SHA256
            DHE-RSA-AES128-SHA
            DHE-RSA-AES256-SHA
            DHE-DSS-AES128-SHA256
            DHE-DSS-AES256-SHA256
            DHE-DSS-AES128-SHA
            DHE-DSS-AES256-SHA
            AES128-GCM-SHA256
            AES256-GCM-SHA384
            AES128-SHA256
            AES256-SHA256
            AES128-SHA
            AES256-SHA
          }.join(":"),
        )
      end

      DEFAULT_CERT_STORE = OpenSSL::X509::Store.new # :nodoc:
      DEFAULT_CERT_STORE.set_default_paths
      DEFAULT_CERT_STORE.flags = OpenSSL::X509::V_FLAG_CRL_CHECK_ALL

      # A callback invoked when DH parameters are required for ephemeral DH key
      # exchange.
      #
      # The callback is invoked with the SSLSocket, a
      # flag indicating the use of an export cipher and the keylength
      # required.
      #
      # The callback must return an OpenSSL::PKey::DH instance of the correct
      # key length.
      #
      # <b>Deprecated in version 3.0.</b> Use #tmp_dh= instead.
      attr_accessor :tmp_dh_callback

      # A callback invoked at connect time to distinguish between multiple
      # server names.
      #
      # The callback is invoked with an SSLSocket and a server name.  The
      # callback must return an SSLContext for the server name or nil.
      attr_accessor :servername_cb

      # call-seq:
      #    SSLContext.new           -> ctx
      #    SSLContext.new(:TLSv1)   -> ctx
      #    SSLContext.new("SSLv23") -> ctx
      #
      # Creates a new SSL context.
      #
      # If an argument is given, #ssl_version= is called with the value. Note
      # that this form is deprecated. New applications should use #min_version=
      # and #max_version= as necessary.
      def initialize(version = nil)
        self.options |= OpenSSL::SSL::OP_ALL
        self.ssl_version = version if version
        self.verify_mode = OpenSSL::SSL::VERIFY_NONE
        self.verify_hostname = false
      end

      ##
      # call-seq:
      #   ctx.set_params(params = {}) -> params
      #
      # Sets saner defaults optimized for the use with HTTP-like protocols.
      #
      # If a Hash _params_ is given, the parameters are overridden with it.
      # The keys in _params_ must be assignment methods on SSLContext.
      #
      # If the verify_mode is not VERIFY_NONE and ca_file, ca_path and
      # cert_store are not set then the system default certificate store is
      # used.
      def set_params(params={})
        params = DEFAULT_PARAMS.merge(params)
        self.options = params.delete(:options) # set before min_version/max_version
        params.each{|name, value| self.__send__("#{name}=", value) }
        if self.verify_mode != OpenSSL::SSL::VERIFY_NONE
          unless self.ca_file or self.ca_path or self.cert_store
            self.cert_store = DEFAULT_CERT_STORE
          end
        end
        return params
      end

      # call-seq:
      #    ctx.min_version = OpenSSL::SSL::TLS1_2_VERSION
      #    ctx.min_version = :TLS1_2
      #    ctx.min_version = nil
      #
      # Sets the lower bound on the supported SSL/TLS protocol version. The
      # version may be specified by an integer constant named
      # OpenSSL::SSL::*_VERSION, a Symbol, or +nil+ which means "any version".
      #
      # Be careful that you don't overwrite OpenSSL::SSL::OP_NO_{SSL,TLS}v*
      # options by #options= once you have called #min_version= or
      # #max_version=.
      #
      # === Example
      #   ctx = OpenSSL::SSL::SSLContext.new
      #   ctx.min_version = OpenSSL::SSL::TLS1_1_VERSION
      #   ctx.max_version = OpenSSL::SSL::TLS1_2_VERSION
      #
      #   sock = OpenSSL::SSL::SSLSocket.new(tcp_sock, ctx)
      #   sock.connect # Initiates a connection using either TLS 1.1 or TLS 1.2
      def min_version=(version)
        set_minmax_proto_version(version, @max_proto_version ||= nil)
        @min_proto_version = version
      end

      # call-seq:
      #    ctx.max_version = OpenSSL::SSL::TLS1_2_VERSION
      #    ctx.max_version = :TLS1_2
      #    ctx.max_version = nil
      #
      # Sets the upper bound of the supported SSL/TLS protocol version. See
      # #min_version= for the possible values.
      def max_version=(version)
        set_minmax_proto_version(@min_proto_version ||= nil, version)
        @max_proto_version = version
      end

      # call-seq:
      #    ctx.ssl_version = :TLSv1
      #    ctx.ssl_version = "SSLv23"
      #
      # Sets the SSL/TLS protocol version for the context. This forces
      # connections to use only the specified protocol version. This is
      # deprecated and only provided for backwards compatibility. Use
      # #min_version= and #max_version= instead.
      #
      # === History
      # As the name hints, this used to call the SSL_CTX_set_ssl_version()
      # function which sets the SSL method used for connections created from
      # the context. As of Ruby/OpenSSL 2.1, this accessor method is
      # implemented to call #min_version= and #max_version= instead.
      def ssl_version=(meth)
        meth = meth.to_s if meth.is_a?(Symbol)
        if /(?<type>_client|_server)\z/ =~ meth
          meth = $`
          if $VERBOSE
            warn "#{caller(1, 1)[0]}: method type #{type.inspect} is ignored"
          end
        end
        version = METHODS_MAP[meth.intern] or
          raise ArgumentError, "unknown SSL method `%s'" % meth
        set_minmax_proto_version(version, version)
        @min_proto_version = @max_proto_version = version
      end

      METHODS_MAP = {
        SSLv23: 0,
        SSLv2: OpenSSL::SSL::SSL2_VERSION,
        SSLv3: OpenSSL::SSL::SSL3_VERSION,
        TLSv1: OpenSSL::SSL::TLS1_VERSION,
        TLSv1_1: OpenSSL::SSL::TLS1_1_VERSION,
        TLSv1_2: OpenSSL::SSL::TLS1_2_VERSION,
      }.freeze
      private_constant :METHODS_MAP

      # The list of available SSL/TLS methods. This constant is only provided
      # for backwards compatibility.
      METHODS = METHODS_MAP.flat_map { |name,|
        [name, :"#{name}_client", :"#{name}_server"]
      }.freeze
      deprecate_constant :METHODS
    end

    module SocketForwarder
      # The file descriptor for the socket.
      def fileno
        to_io.fileno
      end

      def addr
        to_io.addr
      end

      def peeraddr
        to_io.peeraddr
      end

      def setsockopt(level, optname, optval)
        to_io.setsockopt(level, optname, optval)
      end

      def getsockopt(level, optname)
        to_io.getsockopt(level, optname)
      end

      def fcntl(*args)
        to_io.fcntl(*args)
      end

      def closed?
        to_io.closed?
      end

      def do_not_reverse_lookup=(flag)
        to_io.do_not_reverse_lookup = flag
      end
    end

    def verify_certificate_identity(cert, hostname)
      should_verify_common_name = true
      cert.extensions.each{|ext|
        next if ext.oid != "subjectAltName"
        ostr = OpenSSL::ASN1.decode(ext.to_der).value.last
        sequence = OpenSSL::ASN1.decode(ostr.value)
        sequence.value.each{|san|
          case san.tag
          when 2 # dNSName in GeneralName (RFC5280)
            should_verify_common_name = false
            return true if verify_hostname(hostname, san.value)
          when 7 # iPAddress in GeneralName (RFC5280)
            should_verify_common_name = false
            if san.value.size == 4 || san.value.size == 16
              begin
                return true if san.value == IPAddr.new(hostname).hton
              rescue IPAddr::InvalidAddressError
              end
            end
          end
        }
      }
      if should_verify_common_name
        cert.subject.to_a.each{|oid, value|
          if oid == "CN"
            return true if verify_hostname(hostname, value)
          end
        }
      end
      return false
    end
    module_function :verify_certificate_identity

    def verify_hostname(hostname, san) # :nodoc:
      # RFC 5280, IA5String is limited to the set of ASCII characters
      return false unless san.ascii_only?
      return false unless hostname.ascii_only?

      # See RFC 6125, section 6.4.1
      # Matching is case-insensitive.
      san_parts = san.downcase.split(".")

      # TODO: this behavior should probably be more strict
      return san == hostname if san_parts.size < 2

      # Matching is case-insensitive.
      host_parts = hostname.downcase.split(".")

      # RFC 6125, section 6.4.3, subitem 2.
      # If the wildcard character is the only character of the left-most
      # label in the presented identifier, the client SHOULD NOT compare
      # against anything but the left-most label of the reference
      # identifier (e.g., *.example.com would match foo.example.com but
      # not bar.foo.example.com or example.com).
      return false unless san_parts.size == host_parts.size

      # RFC 6125, section 6.4.3, subitem 1.
      # The client SHOULD NOT attempt to match a presented identifier in
      # which the wildcard character comprises a label other than the
      # left-most label (e.g., do not match bar.*.example.net).
      return false unless verify_wildcard(host_parts.shift, san_parts.shift)

      san_parts.join(".") == host_parts.join(".")
    end
    module_function :verify_hostname

    def verify_wildcard(domain_component, san_component) # :nodoc:
      parts = san_component.split("*", -1)

      return false if parts.size > 2
      return san_component == domain_component if parts.size == 1

      # RFC 6125, section 6.4.3, subitem 3.
      # The client SHOULD NOT attempt to match a presented identifier
      # where the wildcard character is embedded within an A-label or
      # U-label of an internationalized domain name.
      return false if domain_component.start_with?("xn--") && san_component != "*"

      parts[0].length + parts[1].length < domain_component.length &&
      domain_component.start_with?(parts[0]) &&
      domain_component.end_with?(parts[1])
    end
    module_function :verify_wildcard

    class SSLSocket
      include Buffering
      include SocketForwarder

      attr_reader :hostname

      # The underlying IO object.
      attr_reader :io
      alias :to_io :io

      # The SSLContext object used in this connection.
      attr_reader :context

      # Whether to close the underlying socket as well, when the SSL/TLS
      # connection is shut down. This defaults to +false+.
      attr_accessor :sync_close

      # call-seq:
      #    ssl.sysclose => nil
      #
      # Sends "close notify" to the peer and tries to shut down the SSL
      # connection gracefully.
      #
      # If sync_close is set to +true+, the underlying IO is also closed.
      def sysclose
        return if closed?
        stop
        io.close if sync_close
      end

      # call-seq:
      #   ssl.post_connection_check(hostname) -> true
      #
      # Perform hostname verification following RFC 6125.
      #
      # This method MUST be called after calling #connect to ensure that the
      # hostname of a remote peer has been verified.
      def post_connection_check(hostname)
        if peer_cert.nil?
          msg = "Peer verification enabled, but no certificate received."
          if using_anon_cipher?
            msg += " Anonymous cipher suite #{cipher[0]} was negotiated. " \
                   "Anonymous suites must be disabled to use peer verification."
          end
          raise SSLError, msg
        end

        unless OpenSSL::SSL.verify_certificate_identity(peer_cert, hostname)
          raise SSLError, "hostname \"#{hostname}\" does not match the server certificate"
        end
        return true
      end

      # call-seq:
      #   ssl.session -> aSession
      #
      # Returns the SSLSession object currently used, or nil if the session is
      # not established.
      def session
        SSL::Session.new(self)
      rescue SSL::Session::SessionError
        nil
      end

      private

      def using_anon_cipher?
        ctx = OpenSSL::SSL::SSLContext.new
        ctx.ciphers = "aNULL"
        ctx.ciphers.include?(cipher)
      end

      def client_cert_cb
        @context.client_cert_cb
      end

      def tmp_dh_callback
        @context.tmp_dh_callback || OpenSSL::SSL::SSLContext::DEFAULT_TMP_DH_CALLBACK
      end

      def session_new_cb
        @context.session_new_cb
      end

      def session_get_cb
        @context.session_get_cb
      end

      class << self

        # call-seq:
        #   open(remote_host, remote_port, local_host=nil, local_port=nil, context: nil)
        #
        # Creates a new instance of SSLSocket.
        # _remote\_host_ and _remote\_port_ are used to open TCPSocket.
        # If _local\_host_ and _local\_port_ are specified,
        # then those parameters are used on the local end to establish the connection.
        # If _context_ is provided,
        # the SSL Sockets initial params will be taken from the context.
        #
        # === Examples
        #
        #   sock = OpenSSL::SSL::SSLSocket.open('localhost', 443)
        #   sock.connect # Initiates a connection to localhost:443
        #
        # with SSLContext:
        #
        #   ctx = OpenSSL::SSL::SSLContext.new
        #   sock = OpenSSL::SSL::SSLSocket.open('localhost', 443, context: ctx)
        #   sock.connect # Initiates a connection to localhost:443 with SSLContext
        def open(remote_host, remote_port, local_host=nil, local_port=nil, context: nil)
          sock = ::TCPSocket.open(remote_host, remote_port, local_host, local_port)
          if context.nil?
            return OpenSSL::SSL::SSLSocket.new(sock)
          else
            return OpenSSL::SSL::SSLSocket.new(sock, context)
          end
        end
      end
    end

    ##
    # SSLServer represents a TCP/IP server socket with Secure Sockets Layer.
    class SSLServer
      include SocketForwarder
      # When true then #accept works exactly the same as TCPServer#accept
      attr_accessor :start_immediately

      # Creates a new instance of SSLServer.
      # * _srv_ is an instance of TCPServer.
      # * _ctx_ is an instance of OpenSSL::SSL::SSLContext.
      def initialize(svr, ctx)
        @svr = svr
        @ctx = ctx
        unless ctx.session_id_context
          # see #6137 - session id may not exceed 32 bytes
          prng = ::Random.new($0.hash)
          session_id = prng.bytes(16).unpack('H*')[0]
          @ctx.session_id_context = session_id
        end
        @start_immediately = true
      end

      # Returns the TCPServer passed to the SSLServer when initialized.
      def to_io
        @svr
      end

      # See TCPServer#listen for details.
      def listen(backlog=Socket::SOMAXCONN)
        @svr.listen(backlog)
      end

      # See BasicSocket#shutdown for details.
      def shutdown(how=Socket::SHUT_RDWR)
        @svr.shutdown(how)
      end

      # Works similar to TCPServer#accept.
      def accept
        # Socket#accept returns [socket, addrinfo].
        # TCPServer#accept returns a socket.
        # The following comma strips addrinfo.
        sock, = @svr.accept
        begin
          ssl = OpenSSL::SSL::SSLSocket.new(sock, @ctx)
          ssl.sync_close = true
          ssl.accept if @start_immediately
          ssl
        rescue Exception => ex
          if ssl
            ssl.close
          else
            sock.close
          end
          raise ex
        end
      end

      # See IO#close for details.
      def close
        @svr.close
      end
    end
  end
end
