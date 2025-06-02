# frozen_string_literal: false
#
# = net/http.rb
#
# Copyright (c) 1999-2007 Yukihiro Matsumoto
# Copyright (c) 1999-2007 Minero Aoki
# Copyright (c) 2001 GOTOU Yuuzou
#
# Written and maintained by Minero Aoki <aamine@loveruby.net>.
# HTTPS support added by GOTOU Yuuzou <gotoyuzo@notwork.org>.
#
# This file is derived from "http-access.rb".
#
# Documented by Minero Aoki; converted to RDoc by William Webber.
#
# This program is free software. You can re-distribute and/or
# modify this program under the same terms of ruby itself ---
# Ruby Distribution License or GNU General Public License.
#
# See Net::HTTP for an overview and examples.
#

require 'net/protocol'
require 'uri'
require 'resolv'
autoload :OpenSSL, 'openssl'

module Net   #:nodoc:

  # :stopdoc:
  class HTTPBadResponse < StandardError; end
  class HTTPHeaderSyntaxError < StandardError; end
  # :startdoc:

  # == An HTTP client API for Ruby.
  #
  # Net::HTTP provides a rich library which can be used to build HTTP
  # user-agents.  For more details about HTTP see
  # [RFC2616](http://www.ietf.org/rfc/rfc2616.txt).
  #
  # Net::HTTP is designed to work closely with URI.  URI::HTTP#host,
  # URI::HTTP#port and URI::HTTP#request_uri are designed to work with
  # Net::HTTP.
  #
  # If you are only performing a few GET requests you should try OpenURI.
  #
  # == Simple Examples
  #
  # All examples assume you have loaded Net::HTTP with:
  #
  #   require 'net/http'
  #
  # This will also require 'uri' so you don't need to require it separately.
  #
  # The Net::HTTP methods in the following section do not persist
  # connections.  They are not recommended if you are performing many HTTP
  # requests.
  #
  # === GET
  #
  #   Net::HTTP.get('example.com', '/index.html') # => String
  #
  # === GET by URI
  #
  #   uri = URI('http://example.com/index.html?count=10')
  #   Net::HTTP.get(uri) # => String
  #
  # === GET with Dynamic Parameters
  #
  #   uri = URI('http://example.com/index.html')
  #   params = { :limit => 10, :page => 3 }
  #   uri.query = URI.encode_www_form(params)
  #
  #   res = Net::HTTP.get_response(uri)
  #   puts res.body if res.is_a?(Net::HTTPSuccess)
  #
  # === POST
  #
  #   uri = URI('http://www.example.com/search.cgi')
  #   res = Net::HTTP.post_form(uri, 'q' => 'ruby', 'max' => '50')
  #   puts res.body
  #
  # === POST with Multiple Values
  #
  #   uri = URI('http://www.example.com/search.cgi')
  #   res = Net::HTTP.post_form(uri, 'q' => ['ruby', 'perl'], 'max' => '50')
  #   puts res.body
  #
  # == How to use Net::HTTP
  #
  # The following example code can be used as the basis of an HTTP user-agent
  # which can perform a variety of request types using persistent
  # connections.
  #
  #   uri = URI('http://example.com/some_path?query=string')
  #
  #   Net::HTTP.start(uri.host, uri.port) do |http|
  #     request = Net::HTTP::Get.new uri
  #
  #     response = http.request request # Net::HTTPResponse object
  #   end
  #
  # Net::HTTP::start immediately creates a connection to an HTTP server which
  # is kept open for the duration of the block.  The connection will remain
  # open for multiple requests in the block if the server indicates it
  # supports persistent connections.
  #
  # If you wish to re-use a connection across multiple HTTP requests without
  # automatically closing it you can use ::new and then call #start and
  # #finish manually.
  #
  # The request types Net::HTTP supports are listed below in the section "HTTP
  # Request Classes".
  #
  # For all the Net::HTTP request objects and shortcut request methods you may
  # supply either a String for the request path or a URI from which Net::HTTP
  # will extract the request path.
  #
  # === Response Data
  #
  #   uri = URI('http://example.com/index.html')
  #   res = Net::HTTP.get_response(uri)
  #
  #   # Headers
  #   res['Set-Cookie']            # => String
  #   res.get_fields('set-cookie') # => Array
  #   res.to_hash['set-cookie']    # => Array
  #   puts "Headers: #{res.to_hash.inspect}"
  #
  #   # Status
  #   puts res.code       # => '200'
  #   puts res.message    # => 'OK'
  #   puts res.class.name # => 'HTTPOK'
  #
  #   # Body
  #   puts res.body
  #
  # === Following Redirection
  #
  # Each Net::HTTPResponse object belongs to a class for its response code.
  #
  # For example, all 2XX responses are instances of a Net::HTTPSuccess
  # subclass, a 3XX response is an instance of a Net::HTTPRedirection
  # subclass and a 200 response is an instance of the Net::HTTPOK class.  For
  # details of response classes, see the section "HTTP Response Classes"
  # below.
  #
  # Using a case statement you can handle various types of responses properly:
  #
  #   def fetch(uri_str, limit = 10)
  #     # You should choose a better exception.
  #     raise ArgumentError, 'too many HTTP redirects' if limit == 0
  #
  #     response = Net::HTTP.get_response(URI(uri_str))
  #
  #     case response
  #     when Net::HTTPSuccess then
  #       response
  #     when Net::HTTPRedirection then
  #       location = response['location']
  #       warn "redirected to #{location}"
  #       fetch(location, limit - 1)
  #     else
  #       response.value
  #     end
  #   end
  #
  #   print fetch('http://www.ruby-lang.org')
  #
  # === POST
  #
  # A POST can be made using the Net::HTTP::Post request class.  This example
  # creates a URL encoded POST body:
  #
  #   uri = URI('http://www.example.com/todo.cgi')
  #   req = Net::HTTP::Post.new(uri)
  #   req.set_form_data('from' => '2005-01-01', 'to' => '2005-03-31')
  #
  #   res = Net::HTTP.start(uri.hostname, uri.port) do |http|
  #     http.request(req)
  #   end
  #
  #   case res
  #   when Net::HTTPSuccess, Net::HTTPRedirection
  #     # OK
  #   else
  #     res.value
  #   end
  #
  # To send multipart/form-data use Net::HTTPHeader#set_form:
  #
  #   req = Net::HTTP::Post.new(uri)
  #   req.set_form([['upload', File.open('foo.bar')]], 'multipart/form-data')
  #
  # Other requests that can contain a body such as PUT can be created in the
  # same way using the corresponding request class (Net::HTTP::Put).
  #
  # === Setting Headers
  #
  # The following example performs a conditional GET using the
  # If-Modified-Since header.  If the files has not been modified since the
  # time in the header a Not Modified response will be returned.  See RFC 2616
  # section 9.3 for further details.
  #
  #   uri = URI('http://example.com/cached_response')
  #   file = File.stat 'cached_response'
  #
  #   req = Net::HTTP::Get.new(uri)
  #   req['If-Modified-Since'] = file.mtime.rfc2822
  #
  #   res = Net::HTTP.start(uri.hostname, uri.port) {|http|
  #     http.request(req)
  #   }
  #
  #   open 'cached_response', 'w' do |io|
  #     io.write res.body
  #   end if res.is_a?(Net::HTTPSuccess)
  #
  # === Basic Authentication
  #
  # Basic authentication is performed according to
  # [RFC2617](http://www.ietf.org/rfc/rfc2617.txt).
  #
  #   uri = URI('http://example.com/index.html?key=value')
  #
  #   req = Net::HTTP::Get.new(uri)
  #   req.basic_auth 'user', 'pass'
  #
  #   res = Net::HTTP.start(uri.hostname, uri.port) {|http|
  #     http.request(req)
  #   }
  #   puts res.body
  #
  # === Streaming Response Bodies
  #
  # By default Net::HTTP reads an entire response into memory.  If you are
  # handling large files or wish to implement a progress bar you can instead
  # stream the body directly to an IO.
  #
  #   uri = URI('http://example.com/large_file')
  #
  #   Net::HTTP.start(uri.host, uri.port) do |http|
  #     request = Net::HTTP::Get.new uri
  #
  #     http.request request do |response|
  #       open 'large_file', 'w' do |io|
  #         response.read_body do |chunk|
  #           io.write chunk
  #         end
  #       end
  #     end
  #   end
  #
  # === HTTPS
  #
  # HTTPS is enabled for an HTTP connection by Net::HTTP#use_ssl=.
  #
  #   uri = URI('https://secure.example.com/some_path?query=string')
  #
  #   Net::HTTP.start(uri.host, uri.port, :use_ssl => true) do |http|
  #     request = Net::HTTP::Get.new uri
  #     response = http.request request # Net::HTTPResponse object
  #   end
  #
  # Or if you simply want to make a GET request, you may pass in an URI
  # object that has an HTTPS URL. Net::HTTP automatically turns on TLS
  # verification if the URI object has a 'https' URI scheme.
  #
  #   uri = URI('https://example.com/')
  #   Net::HTTP.get(uri) # => String
  #
  # In previous versions of Ruby you would need to require 'net/https' to use
  # HTTPS. This is no longer true.
  #
  # === Proxies
  #
  # Net::HTTP will automatically create a proxy from the +http_proxy+
  # environment variable if it is present.  To disable use of +http_proxy+,
  # pass +nil+ for the proxy address.
  #
  # You may also create a custom proxy:
  #
  #   proxy_addr = 'your.proxy.host'
  #   proxy_port = 8080
  #
  #   Net::HTTP.new('example.com', nil, proxy_addr, proxy_port).start { |http|
  #     # always proxy via your.proxy.addr:8080
  #   }
  #
  # See Net::HTTP.new for further details and examples such as proxies that
  # require a username and password.
  #
  # === Compression
  #
  # Net::HTTP automatically adds Accept-Encoding for compression of response
  # bodies and automatically decompresses gzip and deflate responses unless a
  # Range header was sent.
  #
  # Compression can be disabled through the Accept-Encoding: identity header.
  #
  # == HTTP Request Classes
  #
  # Here is the HTTP request class hierarchy.
  #
  # * Net::HTTPRequest
  #   * Net::HTTP::Get
  #   * Net::HTTP::Head
  #   * Net::HTTP::Post
  #   * Net::HTTP::Patch
  #   * Net::HTTP::Put
  #   * Net::HTTP::Proppatch
  #   * Net::HTTP::Lock
  #   * Net::HTTP::Unlock
  #   * Net::HTTP::Options
  #   * Net::HTTP::Propfind
  #   * Net::HTTP::Delete
  #   * Net::HTTP::Move
  #   * Net::HTTP::Copy
  #   * Net::HTTP::Mkcol
  #   * Net::HTTP::Trace
  #
  # == HTTP Response Classes
  #
  # Here is HTTP response class hierarchy.  All classes are defined in Net
  # module and are subclasses of Net::HTTPResponse.
  #
  # HTTPUnknownResponse:: For unhandled HTTP extensions
  # HTTPInformation::                    1xx
  #   HTTPContinue::                        100
  #   HTTPSwitchProtocol::                  101
  #   HTTPProcessing::                      102
  #   HTTPEarlyHints::                      103
  # HTTPSuccess::                        2xx
  #   HTTPOK::                              200
  #   HTTPCreated::                         201
  #   HTTPAccepted::                        202
  #   HTTPNonAuthoritativeInformation::     203
  #   HTTPNoContent::                       204
  #   HTTPResetContent::                    205
  #   HTTPPartialContent::                  206
  #   HTTPMultiStatus::                     207
  #   HTTPAlreadyReported::                 208
  #   HTTPIMUsed::                          226
  # HTTPRedirection::                    3xx
  #   HTTPMultipleChoices::                 300
  #   HTTPMovedPermanently::                301
  #   HTTPFound::                           302
  #   HTTPSeeOther::                        303
  #   HTTPNotModified::                     304
  #   HTTPUseProxy::                        305
  #   HTTPTemporaryRedirect::               307
  #   HTTPPermanentRedirect::               308
  # HTTPClientError::                    4xx
  #   HTTPBadRequest::                      400
  #   HTTPUnauthorized::                    401
  #   HTTPPaymentRequired::                 402
  #   HTTPForbidden::                       403
  #   HTTPNotFound::                        404
  #   HTTPMethodNotAllowed::                405
  #   HTTPNotAcceptable::                   406
  #   HTTPProxyAuthenticationRequired::     407
  #   HTTPRequestTimeOut::                  408
  #   HTTPConflict::                        409
  #   HTTPGone::                            410
  #   HTTPLengthRequired::                  411
  #   HTTPPreconditionFailed::              412
  #   HTTPRequestEntityTooLarge::           413
  #   HTTPRequestURITooLong::               414
  #   HTTPUnsupportedMediaType::            415
  #   HTTPRequestedRangeNotSatisfiable::    416
  #   HTTPExpectationFailed::               417
  #   HTTPMisdirectedRequest::              421
  #   HTTPUnprocessableEntity::             422
  #   HTTPLocked::                          423
  #   HTTPFailedDependency::                424
  #   HTTPUpgradeRequired::                 426
  #   HTTPPreconditionRequired::            428
  #   HTTPTooManyRequests::                 429
  #   HTTPRequestHeaderFieldsTooLarge::     431
  #   HTTPUnavailableForLegalReasons::      451
  # HTTPServerError::                    5xx
  #   HTTPInternalServerError::             500
  #   HTTPNotImplemented::                  501
  #   HTTPBadGateway::                      502
  #   HTTPServiceUnavailable::              503
  #   HTTPGatewayTimeOut::                  504
  #   HTTPVersionNotSupported::             505
  #   HTTPVariantAlsoNegotiates::           506
  #   HTTPInsufficientStorage::             507
  #   HTTPLoopDetected::                    508
  #   HTTPNotExtended::                     510
  #   HTTPNetworkAuthenticationRequired::   511
  #
  # There is also the Net::HTTPBadResponse exception which is raised when
  # there is a protocol error.
  #
  class HTTP < Protocol

    # :stopdoc:
    VERSION = "0.3.0"
    Revision = %q$Revision$.split[1]
    HTTPVersion = '1.1'
    begin
      require 'zlib'
      HAVE_ZLIB=true
    rescue LoadError
      HAVE_ZLIB=false
    end
    # :startdoc:

    # Turns on net/http 1.2 (Ruby 1.8) features.
    # Defaults to ON in Ruby 1.8 or later.
    def HTTP.version_1_2
      true
    end

    # Returns true if net/http is in version 1.2 mode.
    # Defaults to true.
    def HTTP.version_1_2?
      true
    end

    def HTTP.version_1_1?  #:nodoc:
      false
    end

    class << HTTP
      alias is_version_1_1? version_1_1?   #:nodoc:
      alias is_version_1_2? version_1_2?   #:nodoc:
    end

    #
    # short cut methods
    #

    #
    # Gets the body text from the target and outputs it to $stdout.  The
    # target can either be specified as
    # (+uri+, +headers+), or as (+host+, +path+, +port+ = 80); so:
    #
    #    Net::HTTP.get_print URI('http://www.example.com/index.html')
    #
    # or:
    #
    #    Net::HTTP.get_print 'www.example.com', '/index.html'
    #
    # you can also specify request headers:
    #
    #    Net::HTTP.get_print URI('http://www.example.com/index.html'), { 'Accept' => 'text/html' }
    #
    def HTTP.get_print(uri_or_host, path_or_headers = nil, port = nil)
      get_response(uri_or_host, path_or_headers, port) {|res|
        res.read_body do |chunk|
          $stdout.print chunk
        end
      }
      nil
    end

    # Sends a GET request to the target and returns the HTTP response
    # as a string.  The target can either be specified as
    # (+uri+, +headers+), or as (+host+, +path+, +port+ = 80); so:
    #
    #    print Net::HTTP.get(URI('http://www.example.com/index.html'))
    #
    # or:
    #
    #    print Net::HTTP.get('www.example.com', '/index.html')
    #
    # you can also specify request headers:
    #
    #    Net::HTTP.get(URI('http://www.example.com/index.html'), { 'Accept' => 'text/html' })
    #
    def HTTP.get(uri_or_host, path_or_headers = nil, port = nil)
      get_response(uri_or_host, path_or_headers, port).body
    end

    # Sends a GET request to the target and returns the HTTP response
    # as a Net::HTTPResponse object.  The target can either be specified as
    # (+uri+, +headers+), or as (+host+, +path+, +port+ = 80); so:
    #
    #    res = Net::HTTP.get_response(URI('http://www.example.com/index.html'))
    #    print res.body
    #
    # or:
    #
    #    res = Net::HTTP.get_response('www.example.com', '/index.html')
    #    print res.body
    #
    # you can also specify request headers:
    #
    #    Net::HTTP.get_response(URI('http://www.example.com/index.html'), { 'Accept' => 'text/html' })
    #
    def HTTP.get_response(uri_or_host, path_or_headers = nil, port = nil, &block)
      if path_or_headers && !path_or_headers.is_a?(Hash)
        host = uri_or_host
        path = path_or_headers
        new(host, port || HTTP.default_port).start {|http|
          return http.request_get(path, &block)
        }
      else
        uri = uri_or_host
        headers = path_or_headers
        start(uri.hostname, uri.port,
              :use_ssl => uri.scheme == 'https') {|http|
          return http.request_get(uri, headers, &block)
        }
      end
    end

    # Posts data to the specified URI object.
    #
    # Example:
    #
    #   require 'net/http'
    #   require 'uri'
    #
    #   Net::HTTP.post URI('http://www.example.com/api/search'),
    #                  { "q" => "ruby", "max" => "50" }.to_json,
    #                  "Content-Type" => "application/json"
    #
    def HTTP.post(url, data, header = nil)
      start(url.hostname, url.port,
            :use_ssl => url.scheme == 'https' ) {|http|
        http.post(url, data, header)
      }
    end

    # Posts HTML form data to the specified URI object.
    # The form data must be provided as a Hash mapping from String to String.
    # Example:
    #
    #   { "cmd" => "search", "q" => "ruby", "max" => "50" }
    #
    # This method also does Basic Authentication if and only if +url+.user exists.
    # But userinfo for authentication is deprecated (RFC3986).
    # So this feature will be removed.
    #
    # Example:
    #
    #   require 'net/http'
    #
    #   Net::HTTP.post_form URI('http://www.example.com/search.cgi'),
    #                       { "q" => "ruby", "max" => "50" }
    #
    def HTTP.post_form(url, params)
      req = Post.new(url)
      req.form_data = params
      req.basic_auth url.user, url.password if url.user
      start(url.hostname, url.port,
            :use_ssl => url.scheme == 'https' ) {|http|
        http.request(req)
      }
    end

    #
    # HTTP session management
    #

    # The default port to use for HTTP requests; defaults to 80.
    def HTTP.default_port
      http_default_port()
    end

    # The default port to use for HTTP requests; defaults to 80.
    def HTTP.http_default_port
      80
    end

    # The default port to use for HTTPS requests; defaults to 443.
    def HTTP.https_default_port
      443
    end

    def HTTP.socket_type   #:nodoc: obsolete
      BufferedIO
    end

    # :call-seq:
    #   HTTP.start(address, port, p_addr, p_port, p_user, p_pass, &block)
    #   HTTP.start(address, port=nil, p_addr=:ENV, p_port=nil, p_user=nil, p_pass=nil, opt, &block)
    #
    # Creates a new Net::HTTP object, then additionally opens the TCP
    # connection and HTTP session.
    #
    # Arguments are the following:
    # _address_ :: hostname or IP address of the server
    # _port_    :: port of the server
    # _p_addr_  :: address of proxy
    # _p_port_  :: port of proxy
    # _p_user_  :: user of proxy
    # _p_pass_  :: pass of proxy
    # _opt_     :: optional hash
    #
    # _opt_ sets following values by its accessor.
    # The keys are ipaddr, ca_file, ca_path, cert, cert_store, ciphers, keep_alive_timeout,
    # close_on_empty_response, key, open_timeout, read_timeout, write_timeout, ssl_timeout,
    # ssl_version, use_ssl, verify_callback, verify_depth and verify_mode.
    # If you set :use_ssl as true, you can use https and default value of
    # verify_mode is set as OpenSSL::SSL::VERIFY_PEER.
    #
    # If the optional block is given, the newly
    # created Net::HTTP object is passed to it and closed when the
    # block finishes.  In this case, the return value of this method
    # is the return value of the block.  If no block is given, the
    # return value of this method is the newly created Net::HTTP object
    # itself, and the caller is responsible for closing it upon completion
    # using the finish() method.
    def HTTP.start(address, *arg, &block) # :yield: +http+
      arg.pop if opt = Hash.try_convert(arg[-1])
      port, p_addr, p_port, p_user, p_pass = *arg
      p_addr = :ENV if arg.size < 2
      port = https_default_port if !port && opt && opt[:use_ssl]
      http = new(address, port, p_addr, p_port, p_user, p_pass)
      http.ipaddr = opt[:ipaddr] if opt && opt[:ipaddr]

      if opt
        if opt[:use_ssl]
          opt = {verify_mode: OpenSSL::SSL::VERIFY_PEER}.update(opt)
        end
        http.methods.grep(/\A(\w+)=\z/) do |meth|
          key = $1.to_sym
          opt.key?(key) or next
          http.__send__(meth, opt[key])
        end
      end

      http.start(&block)
    end

    class << HTTP
      alias newobj new # :nodoc:
    end

    # Creates a new Net::HTTP object without opening a TCP connection or
    # HTTP session.
    #
    # The +address+ should be a DNS hostname or IP address, the +port+ is the
    # port the server operates on.  If no +port+ is given the default port for
    # HTTP or HTTPS is used.
    #
    # If none of the +p_+ arguments are given, the proxy host and port are
    # taken from the +http_proxy+ environment variable (or its uppercase
    # equivalent) if present.  If the proxy requires authentication you must
    # supply it by hand.  See URI::Generic#find_proxy for details of proxy
    # detection from the environment.  To disable proxy detection set +p_addr+
    # to nil.
    #
    # If you are connecting to a custom proxy, +p_addr+ specifies the DNS name
    # or IP address of the proxy host, +p_port+ the port to use to access the
    # proxy, +p_user+ and +p_pass+ the username and password if authorization
    # is required to use the proxy, and p_no_proxy hosts which do not
    # use the proxy.
    #
    def HTTP.new(address, port = nil, p_addr = :ENV, p_port = nil, p_user = nil, p_pass = nil, p_no_proxy = nil)
      http = super address, port

      if proxy_class? then # from Net::HTTP::Proxy()
        http.proxy_from_env = @proxy_from_env
        http.proxy_address  = @proxy_address
        http.proxy_port     = @proxy_port
        http.proxy_user     = @proxy_user
        http.proxy_pass     = @proxy_pass
      elsif p_addr == :ENV then
        http.proxy_from_env = true
      else
        if p_addr && p_no_proxy && !URI::Generic.use_proxy?(p_addr, p_addr, p_port, p_no_proxy)
          p_addr = nil
          p_port = nil
        end
        http.proxy_address = p_addr
        http.proxy_port    = p_port || default_port
        http.proxy_user    = p_user
        http.proxy_pass    = p_pass
      end

      http
    end

    # Creates a new Net::HTTP object for the specified server address,
    # without opening the TCP connection or initializing the HTTP session.
    # The +address+ should be a DNS hostname or IP address.
    def initialize(address, port = nil)
      @address = address
      @port    = (port || HTTP.default_port)
      @ipaddr = nil
      @local_host = nil
      @local_port = nil
      @curr_http_version = HTTPVersion
      @keep_alive_timeout = 2
      @last_communicated = nil
      @close_on_empty_response = false
      @socket  = nil
      @started = false
      @open_timeout = 60
      @read_timeout = 60
      @write_timeout = 60
      @continue_timeout = nil
      @max_retries = 1
      @debug_output = nil
      @response_body_encoding = false
      @ignore_eof = true

      @proxy_from_env = false
      @proxy_uri      = nil
      @proxy_address  = nil
      @proxy_port     = nil
      @proxy_user     = nil
      @proxy_pass     = nil

      @use_ssl = false
      @ssl_context = nil
      @ssl_session = nil
      @sspi_enabled = false
      SSL_IVNAMES.each do |ivname|
        instance_variable_set ivname, nil
      end
    end

    def inspect
      "#<#{self.class} #{@address}:#{@port} open=#{started?}>"
    end

    # *WARNING* This method opens a serious security hole.
    # Never use this method in production code.
    #
    # Sets an output stream for debugging.
    #
    #   http = Net::HTTP.new(hostname)
    #   http.set_debug_output $stderr
    #   http.start { .... }
    #
    def set_debug_output(output)
      warn 'Net::HTTP#set_debug_output called after HTTP started', uplevel: 1 if started?
      @debug_output = output
    end

    # The DNS host name or IP address to connect to.
    attr_reader :address

    # The port number to connect to.
    attr_reader :port

    # The local host used to establish the connection.
    attr_accessor :local_host

    # The local port used to establish the connection.
    attr_accessor :local_port

    # The encoding to use for the response body.  If Encoding, uses the
    # specified encoding.  If other true value, tries to detect the response
    # body encoding.
    attr_reader :response_body_encoding

    # Set the encoding to use for the response body.  If given a String, find
    # the related Encoding.
    def response_body_encoding=(value)
      value = Encoding.find(value) if value.is_a?(String)
      @response_body_encoding = value
    end

    attr_writer :proxy_from_env
    attr_writer :proxy_address
    attr_writer :proxy_port
    attr_writer :proxy_user
    attr_writer :proxy_pass

    # The IP address to connect to/used to connect to
    def ipaddr
      started? ?  @socket.io.peeraddr[3] : @ipaddr
    end

    # Set the IP address to connect to
    def ipaddr=(addr)
      raise IOError, "ipaddr value changed, but session already started" if started?
      @ipaddr = addr
    end

    # Number of seconds to wait for the connection to open. Any number
    # may be used, including Floats for fractional seconds. If the HTTP
    # object cannot open a connection in this many seconds, it raises a
    # Net::OpenTimeout exception. The default value is 60 seconds.
    attr_accessor :open_timeout

    # Number of seconds to wait for one block to be read (via one read(2)
    # call). Any number may be used, including Floats for fractional
    # seconds. If the HTTP object cannot read data in this many seconds,
    # it raises a Net::ReadTimeout exception. The default value is 60 seconds.
    attr_reader :read_timeout

    # Number of seconds to wait for one block to be written (via one write(2)
    # call). Any number may be used, including Floats for fractional
    # seconds. If the HTTP object cannot write data in this many seconds,
    # it raises a Net::WriteTimeout exception. The default value is 60 seconds.
    # Net::WriteTimeout is not raised on Windows.
    attr_reader :write_timeout

    # Maximum number of times to retry an idempotent request in case of
    # Net::ReadTimeout, IOError, EOFError, Errno::ECONNRESET,
    # Errno::ECONNABORTED, Errno::EPIPE, OpenSSL::SSL::SSLError,
    # Timeout::Error.
    # Should be a non-negative integer number. Zero means no retries.
    # The default value is 1.
    def max_retries=(retries)
      retries = retries.to_int
      if retries < 0
        raise ArgumentError, 'max_retries should be non-negative integer number'
      end
      @max_retries = retries
    end

    attr_reader :max_retries

    # Setter for the read_timeout attribute.
    def read_timeout=(sec)
      @socket.read_timeout = sec if @socket
      @read_timeout = sec
    end

    # Setter for the write_timeout attribute.
    def write_timeout=(sec)
      @socket.write_timeout = sec if @socket
      @write_timeout = sec
    end

    # Seconds to wait for 100 Continue response. If the HTTP object does not
    # receive a response in this many seconds it sends the request body. The
    # default value is +nil+.
    attr_reader :continue_timeout

    # Setter for the continue_timeout attribute.
    def continue_timeout=(sec)
      @socket.continue_timeout = sec if @socket
      @continue_timeout = sec
    end

    # Seconds to reuse the connection of the previous request.
    # If the idle time is less than this Keep-Alive Timeout,
    # Net::HTTP reuses the TCP/IP socket used by the previous communication.
    # The default value is 2 seconds.
    attr_accessor :keep_alive_timeout

    # Whether to ignore EOF when reading response bodies with defined
    # Content-Length headers. For backwards compatibility, the default is true.
    attr_accessor :ignore_eof

    # Returns true if the HTTP session has been started.
    def started?
      @started
    end

    alias active? started?   #:nodoc: obsolete

    attr_accessor :close_on_empty_response

    # Returns true if SSL/TLS is being used with HTTP.
    def use_ssl?
      @use_ssl
    end

    # Turn on/off SSL.
    # This flag must be set before starting session.
    # If you change use_ssl value after session started,
    # a Net::HTTP object raises IOError.
    def use_ssl=(flag)
      flag = flag ? true : false
      if started? and @use_ssl != flag
        raise IOError, "use_ssl value changed, but session already started"
      end
      @use_ssl = flag
    end

    SSL_IVNAMES = [
      :@ca_file,
      :@ca_path,
      :@cert,
      :@cert_store,
      :@ciphers,
      :@extra_chain_cert,
      :@key,
      :@ssl_timeout,
      :@ssl_version,
      :@min_version,
      :@max_version,
      :@verify_callback,
      :@verify_depth,
      :@verify_mode,
      :@verify_hostname,
    ]
    SSL_ATTRIBUTES = [
      :ca_file,
      :ca_path,
      :cert,
      :cert_store,
      :ciphers,
      :extra_chain_cert,
      :key,
      :ssl_timeout,
      :ssl_version,
      :min_version,
      :max_version,
      :verify_callback,
      :verify_depth,
      :verify_mode,
      :verify_hostname,
    ]

    # Sets path of a CA certification file in PEM format.
    #
    # The file can contain several CA certificates.
    attr_accessor :ca_file

    # Sets path of a CA certification directory containing certifications in
    # PEM format.
    attr_accessor :ca_path

    # Sets an OpenSSL::X509::Certificate object as client certificate.
    # (This method is appeared in Michal Rokos's OpenSSL extension).
    attr_accessor :cert

    # Sets the X509::Store to verify peer certificate.
    attr_accessor :cert_store

    # Sets the available ciphers.  See OpenSSL::SSL::SSLContext#ciphers=
    attr_accessor :ciphers

    # Sets the extra X509 certificates to be added to the certificate chain.
    # See OpenSSL::SSL::SSLContext#extra_chain_cert=
    attr_accessor :extra_chain_cert

    # Sets an OpenSSL::PKey::RSA or OpenSSL::PKey::DSA object.
    # (This method is appeared in Michal Rokos's OpenSSL extension.)
    attr_accessor :key

    # Sets the SSL timeout seconds.
    attr_accessor :ssl_timeout

    # Sets the SSL version.  See OpenSSL::SSL::SSLContext#ssl_version=
    attr_accessor :ssl_version

    # Sets the minimum SSL version.  See OpenSSL::SSL::SSLContext#min_version=
    attr_accessor :min_version

    # Sets the maximum SSL version.  See OpenSSL::SSL::SSLContext#max_version=
    attr_accessor :max_version

    # Sets the verify callback for the server certification verification.
    attr_accessor :verify_callback

    # Sets the maximum depth for the certificate chain verification.
    attr_accessor :verify_depth

    # Sets the flags for server the certification verification at beginning of
    # SSL/TLS session.
    #
    # OpenSSL::SSL::VERIFY_NONE or OpenSSL::SSL::VERIFY_PEER are acceptable.
    attr_accessor :verify_mode

    # Sets to check the server certificate is valid for the hostname.
    # See OpenSSL::SSL::SSLContext#verify_hostname=
    attr_accessor :verify_hostname

    # Returns the X.509 certificates the server presented.
    def peer_cert
      if not use_ssl? or not @socket
        return nil
      end
      @socket.io.peer_cert
    end

    # Opens a TCP connection and HTTP session.
    #
    # When this method is called with a block, it passes the Net::HTTP
    # object to the block, and closes the TCP connection and HTTP session
    # after the block has been executed.
    #
    # When called with a block, it returns the return value of the
    # block; otherwise, it returns self.
    #
    def start  # :yield: http
      raise IOError, 'HTTP session already opened' if @started
      if block_given?
        begin
          do_start
          return yield(self)
        ensure
          do_finish
        end
      end
      do_start
      self
    end

    def do_start
      connect
      @started = true
    end
    private :do_start

    def connect
      if use_ssl?
        # reference early to load OpenSSL before connecting,
        # as OpenSSL may take time to load.
        @ssl_context = OpenSSL::SSL::SSLContext.new
      end

      if proxy? then
        conn_addr = proxy_address
        conn_port = proxy_port
      else
        conn_addr = conn_address
        conn_port = port
      end

      debug "opening connection to #{conn_addr}:#{conn_port}..."
      s = Timeout.timeout(@open_timeout, Net::OpenTimeout) {
        begin
          TCPSocket.open(conn_addr, conn_port, @local_host, @local_port)
        rescue => e
          raise e, "Failed to open TCP connection to " +
            "#{conn_addr}:#{conn_port} (#{e.message})"
        end
      }
      s.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
      debug "opened"
      if use_ssl?
        if proxy?
          plain_sock = BufferedIO.new(s, read_timeout: @read_timeout,
                                      write_timeout: @write_timeout,
                                      continue_timeout: @continue_timeout,
                                      debug_output: @debug_output)
          buf = "CONNECT #{conn_address}:#{@port} HTTP/#{HTTPVersion}\r\n"
          buf << "Host: #{@address}:#{@port}\r\n"
          if proxy_user
            credential = ["#{proxy_user}:#{proxy_pass}"].pack('m0')
            buf << "Proxy-Authorization: Basic #{credential}\r\n"
          end
          buf << "\r\n"
          plain_sock.write(buf)
          HTTPResponse.read_new(plain_sock).value
          # assuming nothing left in buffers after successful CONNECT response
        end

        ssl_parameters = Hash.new
        iv_list = instance_variables
        SSL_IVNAMES.each_with_index do |ivname, i|
          if iv_list.include?(ivname)
            value = instance_variable_get(ivname)
            unless value.nil?
              ssl_parameters[SSL_ATTRIBUTES[i]] = value
            end
          end
        end
        @ssl_context.set_params(ssl_parameters)
        unless @ssl_context.session_cache_mode.nil? # a dummy method on JRuby
          @ssl_context.session_cache_mode =
              OpenSSL::SSL::SSLContext::SESSION_CACHE_CLIENT |
                  OpenSSL::SSL::SSLContext::SESSION_CACHE_NO_INTERNAL_STORE
        end
        if @ssl_context.respond_to?(:session_new_cb) # not implemented under JRuby
          @ssl_context.session_new_cb = proc {|sock, sess| @ssl_session = sess }
        end

        # Still do the post_connection_check below even if connecting
        # to IP address
        verify_hostname = @ssl_context.verify_hostname

        # Server Name Indication (SNI) RFC 3546/6066
        case @address
        when Resolv::IPv4::Regex, Resolv::IPv6::Regex
          # don't set SNI, as IP addresses in SNI is not valid
          # per RFC 6066, section 3.

          # Avoid openssl warning
          @ssl_context.verify_hostname = false
        else
          ssl_host_address = @address
        end

        debug "starting SSL for #{conn_addr}:#{conn_port}..."
        s = OpenSSL::SSL::SSLSocket.new(s, @ssl_context)
        s.sync_close = true
        s.hostname = ssl_host_address if s.respond_to?(:hostname=) && ssl_host_address

        if @ssl_session and
           Process.clock_gettime(Process::CLOCK_REALTIME) < @ssl_session.time.to_f + @ssl_session.timeout
          s.session = @ssl_session
        end
        ssl_socket_connect(s, @open_timeout)
        if (@ssl_context.verify_mode != OpenSSL::SSL::VERIFY_NONE) && verify_hostname
          s.post_connection_check(@address)
        end
        debug "SSL established, protocol: #{s.ssl_version}, cipher: #{s.cipher[0]}"
      end
      @socket = BufferedIO.new(s, read_timeout: @read_timeout,
                               write_timeout: @write_timeout,
                               continue_timeout: @continue_timeout,
                               debug_output: @debug_output)
      @last_communicated = nil
      on_connect
    rescue => exception
      if s
        debug "Conn close because of connect error #{exception}"
        s.close
      end
      raise
    end
    private :connect

    def on_connect
    end
    private :on_connect

    # Finishes the HTTP session and closes the TCP connection.
    # Raises IOError if the session has not been started.
    def finish
      raise IOError, 'HTTP session not yet started' unless started?
      do_finish
    end

    def do_finish
      @started = false
      @socket.close if @socket
      @socket = nil
    end
    private :do_finish

    #
    # proxy
    #

    public

    # no proxy
    @is_proxy_class = false
    @proxy_from_env = false
    @proxy_addr = nil
    @proxy_port = nil
    @proxy_user = nil
    @proxy_pass = nil

    # Creates an HTTP proxy class which behaves like Net::HTTP, but
    # performs all access via the specified proxy.
    #
    # This class is obsolete.  You may pass these same parameters directly to
    # Net::HTTP.new.  See Net::HTTP.new for details of the arguments.
    def HTTP.Proxy(p_addr = :ENV, p_port = nil, p_user = nil, p_pass = nil)
      return self unless p_addr

      Class.new(self) {
        @is_proxy_class = true

        if p_addr == :ENV then
          @proxy_from_env = true
          @proxy_address = nil
          @proxy_port    = nil
        else
          @proxy_from_env = false
          @proxy_address = p_addr
          @proxy_port    = p_port || default_port
        end

        @proxy_user = p_user
        @proxy_pass = p_pass
      }
    end

    class << HTTP
      # returns true if self is a class which was created by HTTP::Proxy.
      def proxy_class?
        defined?(@is_proxy_class) ? @is_proxy_class : false
      end

      # Address of proxy host. If Net::HTTP does not use a proxy, nil.
      attr_reader :proxy_address

      # Port number of proxy host. If Net::HTTP does not use a proxy, nil.
      attr_reader :proxy_port

      # User name for accessing proxy. If Net::HTTP does not use a proxy, nil.
      attr_reader :proxy_user

      # User password for accessing proxy. If Net::HTTP does not use a proxy,
      # nil.
      attr_reader :proxy_pass
    end

    # True if requests for this connection will be proxied
    def proxy?
      !!(@proxy_from_env ? proxy_uri : @proxy_address)
    end

    # True if the proxy for this connection is determined from the environment
    def proxy_from_env?
      @proxy_from_env
    end

    # The proxy URI determined from the environment for this connection.
    def proxy_uri # :nodoc:
      return if @proxy_uri == false
      @proxy_uri ||= URI::HTTP.new(
        "http".freeze, nil, address, port, nil, nil, nil, nil, nil
      ).find_proxy || false
      @proxy_uri || nil
    end

    # The address of the proxy server, if one is configured.
    def proxy_address
      if @proxy_from_env then
        proxy_uri&.hostname
      else
        @proxy_address
      end
    end

    # The port of the proxy server, if one is configured.
    def proxy_port
      if @proxy_from_env then
        proxy_uri&.port
      else
        @proxy_port
      end
    end

    # The username of the proxy server, if one is configured.
    def proxy_user
      if @proxy_from_env
        user = proxy_uri&.user
        unescape(user) if user
      else
        @proxy_user
      end
    end

    # The password of the proxy server, if one is configured.
    def proxy_pass
      if @proxy_from_env
        pass = proxy_uri&.password
        unescape(pass) if pass
      else
        @proxy_pass
      end
    end

    alias proxyaddr proxy_address   #:nodoc: obsolete
    alias proxyport proxy_port      #:nodoc: obsolete

    private

    def unescape(value)
      require 'cgi/util'
      CGI.unescape(value)
    end

    # without proxy, obsolete

    def conn_address # :nodoc:
      @ipaddr || address()
    end

    def conn_port # :nodoc:
      port()
    end

    def edit_path(path)
      if proxy?
        if path.start_with?("ftp://") || use_ssl?
          path
        else
          "http://#{addr_port}#{path}"
        end
      else
        path
      end
    end

    #
    # HTTP operations
    #

    public

    # Retrieves data from +path+ on the connected-to host which may be an
    # absolute path String or a URI to extract the path from.
    #
    # +initheader+ must be a Hash like { 'Accept' => '*/*', ... },
    # and it defaults to an empty hash.
    # If +initheader+ doesn't have the key 'accept-encoding', then
    # a value of "gzip;q=1.0,deflate;q=0.6,identity;q=0.3" is used,
    # so that gzip compression is used in preference to deflate
    # compression, which is used in preference to no compression.
    # Ruby doesn't have libraries to support the compress (Lempel-Ziv)
    # compression, so that is not supported.  The intent of this is
    # to reduce bandwidth by default.   If this routine sets up
    # compression, then it does the decompression also, removing
    # the header as well to prevent confusion.  Otherwise
    # it leaves the body as it found it.
    #
    # This method returns a Net::HTTPResponse object.
    #
    # If called with a block, yields each fragment of the
    # entity body in turn as a string as it is read from
    # the socket.  Note that in this case, the returned response
    # object will *not* contain a (meaningful) body.
    #
    # +dest+ argument is obsolete.
    # It still works but you must not use it.
    #
    # This method never raises an exception.
    #
    #     response = http.get('/index.html')
    #
    #     # using block
    #     File.open('result.txt', 'w') {|f|
    #       http.get('/~foo/') do |str|
    #         f.write str
    #       end
    #     }
    #
    def get(path, initheader = nil, dest = nil, &block) # :yield: +body_segment+
      res = nil
      request(Get.new(path, initheader)) {|r|
        r.read_body dest, &block
        res = r
      }
      res
    end

    # Gets only the header from +path+ on the connected-to host.
    # +header+ is a Hash like { 'Accept' => '*/*', ... }.
    #
    # This method returns a Net::HTTPResponse object.
    #
    # This method never raises an exception.
    #
    #     response = nil
    #     Net::HTTP.start('some.www.server', 80) {|http|
    #       response = http.head('/index.html')
    #     }
    #     p response['content-type']
    #
    def head(path, initheader = nil)
      request(Head.new(path, initheader))
    end

    # Posts +data+ (must be a String) to +path+. +header+ must be a Hash
    # like { 'Accept' => '*/*', ... }.
    #
    # This method returns a Net::HTTPResponse object.
    #
    # If called with a block, yields each fragment of the
    # entity body in turn as a string as it is read from
    # the socket.  Note that in this case, the returned response
    # object will *not* contain a (meaningful) body.
    #
    # +dest+ argument is obsolete.
    # It still works but you must not use it.
    #
    # This method never raises exception.
    #
    #     response = http.post('/cgi-bin/search.rb', 'query=foo')
    #
    #     # using block
    #     File.open('result.txt', 'w') {|f|
    #       http.post('/cgi-bin/search.rb', 'query=foo') do |str|
    #         f.write str
    #       end
    #     }
    #
    # You should set Content-Type: header field for POST.
    # If no Content-Type: field given, this method uses
    # "application/x-www-form-urlencoded" by default.
    #
    def post(path, data, initheader = nil, dest = nil, &block) # :yield: +body_segment+
      send_entity(path, data, initheader, dest, Post, &block)
    end

    # Sends a PATCH request to the +path+ and gets a response,
    # as an HTTPResponse object.
    def patch(path, data, initheader = nil, dest = nil, &block) # :yield: +body_segment+
      send_entity(path, data, initheader, dest, Patch, &block)
    end

    def put(path, data, initheader = nil)   #:nodoc:
      request(Put.new(path, initheader), data)
    end

    # Sends a PROPPATCH request to the +path+ and gets a response,
    # as an HTTPResponse object.
    def proppatch(path, body, initheader = nil)
      request(Proppatch.new(path, initheader), body)
    end

    # Sends a LOCK request to the +path+ and gets a response,
    # as an HTTPResponse object.
    def lock(path, body, initheader = nil)
      request(Lock.new(path, initheader), body)
    end

    # Sends a UNLOCK request to the +path+ and gets a response,
    # as an HTTPResponse object.
    def unlock(path, body, initheader = nil)
      request(Unlock.new(path, initheader), body)
    end

    # Sends a OPTIONS request to the +path+ and gets a response,
    # as an HTTPResponse object.
    def options(path, initheader = nil)
      request(Options.new(path, initheader))
    end

    # Sends a PROPFIND request to the +path+ and gets a response,
    # as an HTTPResponse object.
    def propfind(path, body = nil, initheader = {'Depth' => '0'})
      request(Propfind.new(path, initheader), body)
    end

    # Sends a DELETE request to the +path+ and gets a response,
    # as an HTTPResponse object.
    def delete(path, initheader = {'Depth' => 'Infinity'})
      request(Delete.new(path, initheader))
    end

    # Sends a MOVE request to the +path+ and gets a response,
    # as an HTTPResponse object.
    def move(path, initheader = nil)
      request(Move.new(path, initheader))
    end

    # Sends a COPY request to the +path+ and gets a response,
    # as an HTTPResponse object.
    def copy(path, initheader = nil)
      request(Copy.new(path, initheader))
    end

    # Sends a MKCOL request to the +path+ and gets a response,
    # as an HTTPResponse object.
    def mkcol(path, body = nil, initheader = nil)
      request(Mkcol.new(path, initheader), body)
    end

    # Sends a TRACE request to the +path+ and gets a response,
    # as an HTTPResponse object.
    def trace(path, initheader = nil)
      request(Trace.new(path, initheader))
    end

    # Sends a GET request to the +path+.
    # Returns the response as a Net::HTTPResponse object.
    #
    # When called with a block, passes an HTTPResponse object to the block.
    # The body of the response will not have been read yet;
    # the block can process it using HTTPResponse#read_body,
    # if desired.
    #
    # Returns the response.
    #
    # This method never raises Net::* exceptions.
    #
    #     response = http.request_get('/index.html')
    #     # The entity body is already read in this case.
    #     p response['content-type']
    #     puts response.body
    #
    #     # Using a block
    #     http.request_get('/index.html') {|response|
    #       p response['content-type']
    #       response.read_body do |str|   # read body now
    #         print str
    #       end
    #     }
    #
    def request_get(path, initheader = nil, &block) # :yield: +response+
      request(Get.new(path, initheader), &block)
    end

    # Sends a HEAD request to the +path+ and returns the response
    # as a Net::HTTPResponse object.
    #
    # Returns the response.
    #
    # This method never raises Net::* exceptions.
    #
    #     response = http.request_head('/index.html')
    #     p response['content-type']
    #
    def request_head(path, initheader = nil, &block)
      request(Head.new(path, initheader), &block)
    end

    # Sends a POST request to the +path+.
    #
    # Returns the response as a Net::HTTPResponse object.
    #
    # When called with a block, the block is passed an HTTPResponse
    # object.  The body of that response will not have been read yet;
    # the block can process it using HTTPResponse#read_body, if desired.
    #
    # Returns the response.
    #
    # This method never raises Net::* exceptions.
    #
    #     # example
    #     response = http.request_post('/cgi-bin/nice.rb', 'datadatadata...')
    #     p response.status
    #     puts response.body          # body is already read in this case
    #
    #     # using block
    #     http.request_post('/cgi-bin/nice.rb', 'datadatadata...') {|response|
    #       p response.status
    #       p response['content-type']
    #       response.read_body do |str|   # read body now
    #         print str
    #       end
    #     }
    #
    def request_post(path, data, initheader = nil, &block) # :yield: +response+
      request Post.new(path, initheader), data, &block
    end

    def request_put(path, data, initheader = nil, &block)   #:nodoc:
      request Put.new(path, initheader), data, &block
    end

    alias get2   request_get    #:nodoc: obsolete
    alias head2  request_head   #:nodoc: obsolete
    alias post2  request_post   #:nodoc: obsolete
    alias put2   request_put    #:nodoc: obsolete


    # Sends an HTTP request to the HTTP server.
    # Also sends a DATA string if +data+ is given.
    #
    # Returns a Net::HTTPResponse object.
    #
    # This method never raises Net::* exceptions.
    #
    #    response = http.send_request('GET', '/index.html')
    #    puts response.body
    #
    def send_request(name, path, data = nil, header = nil)
      has_response_body = name != 'HEAD'
      r = HTTPGenericRequest.new(name,(data ? true : false),has_response_body,path,header)
      request r, data
    end

    # Sends an HTTPRequest object +req+ to the HTTP server.
    #
    # If +req+ is a Net::HTTP::Post or Net::HTTP::Put request containing
    # data, the data is also sent. Providing data for a Net::HTTP::Head or
    # Net::HTTP::Get request results in an ArgumentError.
    #
    # Returns an HTTPResponse object.
    #
    # When called with a block, passes an HTTPResponse object to the block.
    # The body of the response will not have been read yet;
    # the block can process it using HTTPResponse#read_body,
    # if desired.
    #
    # This method never raises Net::* exceptions.
    #
    def request(req, body = nil, &block)  # :yield: +response+
      unless started?
        start {
          req['connection'] ||= 'close'
          return request(req, body, &block)
        }
      end
      if proxy_user()
        req.proxy_basic_auth proxy_user(), proxy_pass() unless use_ssl?
      end
      req.set_body_internal body
      res = transport_request(req, &block)
      if sspi_auth?(res)
        sspi_auth(req)
        res = transport_request(req, &block)
      end
      res
    end

    private

    # Executes a request which uses a representation
    # and returns its body.
    def send_entity(path, data, initheader, dest, type, &block)
      res = nil
      request(type.new(path, initheader), data) {|r|
        r.read_body dest, &block
        res = r
      }
      res
    end

    IDEMPOTENT_METHODS_ = %w/GET HEAD PUT DELETE OPTIONS TRACE/ # :nodoc:

    def transport_request(req)
      count = 0
      begin
        begin_transport req
        res = catch(:response) {
          begin
            req.exec @socket, @curr_http_version, edit_path(req.path)
          rescue Errno::EPIPE
            # Failure when writing full request, but we can probably
            # still read the received response.
          end

          begin
            res = HTTPResponse.read_new(@socket)
            res.decode_content = req.decode_content
            res.body_encoding = @response_body_encoding
            res.ignore_eof = @ignore_eof
          end while res.kind_of?(HTTPInformation)

          res.uri = req.uri

          res
        }
        res.reading_body(@socket, req.response_body_permitted?) {
          yield res if block_given?
        }
      rescue Net::OpenTimeout
        raise
      rescue Net::ReadTimeout, IOError, EOFError,
             Errno::ECONNRESET, Errno::ECONNABORTED, Errno::EPIPE, Errno::ETIMEDOUT,
             # avoid a dependency on OpenSSL
             defined?(OpenSSL::SSL) ? OpenSSL::SSL::SSLError : IOError,
             Timeout::Error => exception
        if count < max_retries && IDEMPOTENT_METHODS_.include?(req.method)
          count += 1
          @socket.close if @socket
          debug "Conn close because of error #{exception}, and retry"
          retry
        end
        debug "Conn close because of error #{exception}"
        @socket.close if @socket
        raise
      end

      end_transport req, res
      res
    rescue => exception
      debug "Conn close because of error #{exception}"
      @socket.close if @socket
      raise exception
    end

    def begin_transport(req)
      if @socket.closed?
        connect
      elsif @last_communicated
        if @last_communicated + @keep_alive_timeout < Process.clock_gettime(Process::CLOCK_MONOTONIC)
          debug 'Conn close because of keep_alive_timeout'
          @socket.close
          connect
        elsif @socket.io.to_io.wait_readable(0) && @socket.eof?
          debug "Conn close because of EOF"
          @socket.close
          connect
        end
      end

      if not req.response_body_permitted? and @close_on_empty_response
        req['connection'] ||= 'close'
      end

      req.update_uri address, port, use_ssl?
      req['host'] ||= addr_port()
    end

    def end_transport(req, res)
      @curr_http_version = res.http_version
      @last_communicated = nil
      if @socket.closed?
        debug 'Conn socket closed'
      elsif not res.body and @close_on_empty_response
        debug 'Conn close'
        @socket.close
      elsif keep_alive?(req, res)
        debug 'Conn keep-alive'
        @last_communicated = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      else
        debug 'Conn close'
        @socket.close
      end
    end

    def keep_alive?(req, res)
      return false if req.connection_close?
      if @curr_http_version <= '1.0'
        res.connection_keep_alive?
      else   # HTTP/1.1 or later
        not res.connection_close?
      end
    end

    def sspi_auth?(res)
      return false unless @sspi_enabled
      if res.kind_of?(HTTPProxyAuthenticationRequired) and
          proxy? and res["Proxy-Authenticate"].include?("Negotiate")
        begin
          require 'win32/sspi'
          true
        rescue LoadError
          false
        end
      else
        false
      end
    end

    def sspi_auth(req)
      n = Win32::SSPI::NegotiateAuth.new
      req["Proxy-Authorization"] = "Negotiate #{n.get_initial_token}"
      # Some versions of ISA will close the connection if this isn't present.
      req["Connection"] = "Keep-Alive"
      req["Proxy-Connection"] = "Keep-Alive"
      res = transport_request(req)
      authphrase = res["Proxy-Authenticate"]  or return res
      req["Proxy-Authorization"] = "Negotiate #{n.complete_authentication(authphrase)}"
    rescue => err
      raise HTTPAuthenticationError.new('HTTP authentication failed', err)
    end

    #
    # utils
    #

    private

    def addr_port
      addr = address
      addr = "[#{addr}]" if addr.include?(":")
      default_port = use_ssl? ? HTTP.https_default_port : HTTP.http_default_port
      default_port == port ? addr : "#{addr}:#{port}"
    end

    # Adds a message to debugging output
    def debug(msg)
      return unless @debug_output
      @debug_output << msg
      @debug_output << "\n"
    end

    alias_method :D, :debug
  end

end

require_relative 'http/exceptions'

require_relative 'http/header'

require_relative 'http/generic_request'
require_relative 'http/request'
require_relative 'http/requests'

require_relative 'http/response'
require_relative 'http/responses'

require_relative 'http/proxy_delta'

require_relative 'http/backward'
