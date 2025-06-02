require_relative '../../../../../vendored_net_http'
require_relative '../../../../../vendored_uri'
require 'cgi' # for escaping
require_relative '../../../../connection_pool/lib/connection_pool'

autoload :OpenSSL, 'openssl'

##
# Persistent connections for Gem::Net::HTTP
#
# Gem::Net::HTTP::Persistent maintains persistent connections across all the
# servers you wish to talk to.  For each host:port you communicate with a
# single persistent connection is created.
#
# Connections will be shared across threads through a connection pool to
# increase reuse of connections.
#
# You can shut down any remaining HTTP connections when done by calling
# #shutdown.
#
# Example:
#
#   require 'bundler/vendor/net-http-persistent/lib/net/http/persistent'
#
#   uri = Gem::URI 'http://example.com/awesome/web/service'
#
#   http = Gem::Net::HTTP::Persistent.new
#
#   # perform a GET
#   response = http.request uri
#
#   # or
#
#   get = Gem::Net::HTTP::Get.new uri.request_uri
#   response = http.request get
#
#   # create a POST
#   post_uri = uri + 'create'
#   post = Gem::Net::HTTP::Post.new post_uri.path
#   post.set_form_data 'some' => 'cool data'
#
#   # perform the POST, the Gem::URI is always required
#   response http.request post_uri, post
#
# Note that for GET, HEAD and other requests that do not have a body you want
# to use Gem::URI#request_uri not Gem::URI#path.  The request_uri contains the query
# params which are sent in the body for other requests.
#
# == TLS/SSL
#
# TLS connections are automatically created depending upon the scheme of the
# Gem::URI.  TLS connections are automatically verified against the default
# certificate store for your computer.  You can override this by changing
# verify_mode or by specifying an alternate cert_store.
#
# Here are the TLS settings, see the individual methods for documentation:
#
# #certificate        :: This client's certificate
# #ca_file            :: The certificate-authorities
# #ca_path            :: Directory with certificate-authorities
# #cert_store         :: An SSL certificate store
# #ciphers            :: List of SSl ciphers allowed
# #private_key        :: The client's SSL private key
# #reuse_ssl_sessions :: Reuse a previously opened SSL session for a new
#                        connection
# #ssl_timeout        :: Session lifetime
# #ssl_version        :: Which specific SSL version to use
# #verify_callback    :: For server certificate verification
# #verify_depth       :: Depth of certificate verification
# #verify_mode        :: How connections should be verified
# #verify_hostname    :: Use hostname verification for server certificate
#                        during the handshake
#
# == Proxies
#
# A proxy can be set through #proxy= or at initialization time by providing a
# second argument to ::new.  The proxy may be the Gem::URI of the proxy server or
# <code>:ENV</code> which will consult environment variables.
#
# See #proxy= and #proxy_from_env for details.
#
# == Headers
#
# Headers may be specified for use in every request.  #headers are appended to
# any headers on the request.  #override_headers replace existing headers on
# the request.
#
# The difference between the two can be seen in setting the User-Agent.  Using
# <code>http.headers['User-Agent'] = 'MyUserAgent'</code> will send "Ruby,
# MyUserAgent" while <code>http.override_headers['User-Agent'] =
# 'MyUserAgent'</code> will send "MyUserAgent".
#
# == Tuning
#
# === Segregation
#
# Each Gem::Net::HTTP::Persistent instance has its own pool of connections.  There
# is no sharing with other instances (as was true in earlier versions).
#
# === Idle Timeout
#
# If a connection hasn't been used for this number of seconds it will
# automatically be reset upon the next use to avoid attempting to send to a
# closed connection.  The default value is 5 seconds. nil means no timeout.
# Set through #idle_timeout.
#
# Reducing this value may help avoid the "too many connection resets" error
# when sending non-idempotent requests while increasing this value will cause
# fewer round-trips.
#
# === Read Timeout
#
# The amount of time allowed between reading two chunks from the socket.  Set
# through #read_timeout
#
# === Max Requests
#
# The number of requests that should be made before opening a new connection.
# Typically many keep-alive capable servers tune this to 100 or less, so the
# 101st request will fail with ECONNRESET. If unset (default), this value has
# no effect, if set, connections will be reset on the request after
# max_requests.
#
# === Open Timeout
#
# The amount of time to wait for a connection to be opened.  Set through
# #open_timeout.
#
# === Socket Options
#
# Socket options may be set on newly-created connections.  See #socket_options
# for details.
#
# === Connection Termination
#
# If you are done using the Gem::Net::HTTP::Persistent instance you may shut down
# all the connections in the current thread with #shutdown.  This is not
# recommended for normal use, it should only be used when it will be several
# minutes before you make another HTTP request.
#
# If you are using multiple threads, call #shutdown in each thread when the
# thread is done making requests.  If you don't call shutdown, that's OK.
# Ruby will automatically garbage collect and shutdown your HTTP connections
# when the thread terminates.

class Gem::Net::HTTP::Persistent

  ##
  # The beginning of Time

  EPOCH = Time.at 0 # :nodoc:

  ##
  # Is OpenSSL available?  This test works with autoload

  HAVE_OPENSSL = defined? OpenSSL::SSL # :nodoc:

  ##
  # The default connection pool size is 1/4 the allowed open files
  # (<code>ulimit -n</code>) or 256 if your OS does not support file handle
  # limits (typically windows).

  if Process.const_defined? :RLIMIT_NOFILE
    open_file_limits = Process.getrlimit(Process::RLIMIT_NOFILE)

    # Under JRuby on Windows Process responds to `getrlimit` but returns something that does not match docs
    if open_file_limits.respond_to?(:first)
      DEFAULT_POOL_SIZE = open_file_limits.first / 4
    else
      DEFAULT_POOL_SIZE = 256
    end
  else
    DEFAULT_POOL_SIZE = 256
  end

  ##
  # The version of Gem::Net::HTTP::Persistent you are using

  VERSION = '4.0.4'

  ##
  # Error class for errors raised by Gem::Net::HTTP::Persistent.  Various
  # SystemCallErrors are re-raised with a human-readable message under this
  # class.

  class Error < StandardError; end

  ##
  # Use this method to detect the idle timeout of the host at +uri+.  The
  # value returned can be used to configure #idle_timeout.  +max+ controls the
  # maximum idle timeout to detect.
  #
  # After
  #
  # Idle timeout detection is performed by creating a connection then
  # performing a HEAD request in a loop until the connection terminates
  # waiting one additional second per loop.
  #
  # NOTE:  This may not work on ruby > 1.9.

  def self.detect_idle_timeout uri, max = 10
    uri = Gem::URI uri unless Gem::URI::Generic === uri
    uri += '/'

    req = Gem::Net::HTTP::Head.new uri.request_uri

    http = new 'net-http-persistent detect_idle_timeout'

    http.connection_for uri do |connection|
      sleep_time = 0

      http = connection.http

      loop do
        response = http.request req

        $stderr.puts "HEAD #{uri} => #{response.code}" if $DEBUG

        unless Gem::Net::HTTPOK === response then
          raise Error, "bad response code #{response.code} detecting idle timeout"
        end

        break if sleep_time >= max

        sleep_time += 1

        $stderr.puts "sleeping #{sleep_time}" if $DEBUG
        sleep sleep_time
      end
    end
  rescue
    # ignore StandardErrors, we've probably found the idle timeout.
  ensure
    return sleep_time unless $!
  end

  ##
  # This client's OpenSSL::X509::Certificate

  attr_reader :certificate

  ##
  # For Gem::Net::HTTP parity

  alias cert certificate

  ##
  # An SSL certificate authority.  Setting this will set verify_mode to
  # VERIFY_PEER.

  attr_reader :ca_file

  ##
  # A directory of SSL certificates to be used as certificate authorities.
  # Setting this will set verify_mode to VERIFY_PEER.

  attr_reader :ca_path

  ##
  # An SSL certificate store.  Setting this will override the default
  # certificate store.  See verify_mode for more information.

  attr_reader :cert_store

  ##
  # The ciphers allowed for SSL connections

  attr_reader :ciphers

  ##
  # Sends debug_output to this IO via Gem::Net::HTTP#set_debug_output.
  #
  # Never use this method in production code, it causes a serious security
  # hole.

  attr_accessor :debug_output

  ##
  # Current connection generation

  attr_reader :generation # :nodoc:

  ##
  # Headers that are added to every request using Gem::Net::HTTP#add_field

  attr_reader :headers

  ##
  # Maps host:port to an HTTP version.  This allows us to enable version
  # specific features.

  attr_reader :http_versions

  ##
  # Maximum time an unused connection can remain idle before being
  # automatically closed.

  attr_accessor :idle_timeout

  ##
  # Maximum number of requests on a connection before it is considered expired
  # and automatically closed.

  attr_accessor :max_requests

  ##
  # Number of retries to perform if a request fails.
  #
  # See also #max_retries=, Gem::Net::HTTP#max_retries=.

  attr_reader :max_retries

  ##
  # The value sent in the Keep-Alive header.  Defaults to 30.  Not needed for
  # HTTP/1.1 servers.
  #
  # This may not work correctly for HTTP/1.0 servers
  #
  # This method may be removed in a future version as RFC 2616 does not
  # require this header.

  attr_accessor :keep_alive

  ##
  # The name for this collection of persistent connections.

  attr_reader :name

  ##
  # Seconds to wait until a connection is opened.  See Gem::Net::HTTP#open_timeout

  attr_accessor :open_timeout

  ##
  # Headers that are added to every request using Gem::Net::HTTP#[]=

  attr_reader :override_headers

  ##
  # This client's SSL private key

  attr_reader :private_key

  ##
  # For Gem::Net::HTTP parity

  alias key private_key

  ##
  # The URL through which requests will be proxied

  attr_reader :proxy_uri

  ##
  # List of host suffixes which will not be proxied

  attr_reader :no_proxy

  ##
  # Test-only accessor for the connection pool

  attr_reader :pool # :nodoc:

  ##
  # Seconds to wait until reading one block.  See Gem::Net::HTTP#read_timeout

  attr_accessor :read_timeout

  ##
  # Seconds to wait until writing one block.  See Gem::Net::HTTP#write_timeout

  attr_accessor :write_timeout

  ##
  # By default SSL sessions are reused to avoid extra SSL handshakes.  Set
  # this to false if you have problems communicating with an HTTPS server
  # like:
  #
  #   SSL_connect [...] read finished A: unexpected message (OpenSSL::SSL::SSLError)

  attr_accessor :reuse_ssl_sessions

  ##
  # An array of options for Socket#setsockopt.
  #
  # By default the TCP_NODELAY option is set on sockets.
  #
  # To set additional options append them to this array:
  #
  #   http.socket_options << [Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, 1]

  attr_reader :socket_options

  ##
  # Current SSL connection generation

  attr_reader :ssl_generation # :nodoc:

  ##
  # SSL session lifetime

  attr_reader :ssl_timeout

  ##
  # SSL version to use.
  #
  # By default, the version will be negotiated automatically between client
  # and server.  Ruby 1.9 and newer only. Deprecated since Ruby 2.5.

  attr_reader :ssl_version

  ##
  # Minimum SSL version to use, e.g. :TLS1_1
  #
  # By default, the version will be negotiated automatically between client
  # and server.  Ruby 2.5 and newer only.

  attr_reader :min_version

  ##
  # Maximum SSL version to use, e.g. :TLS1_2
  #
  # By default, the version will be negotiated automatically between client
  # and server.  Ruby 2.5 and newer only.

  attr_reader :max_version

  ##
  # Where this instance's last-use times live in the thread local variables

  attr_reader :timeout_key # :nodoc:

  ##
  # SSL verification callback.  Used when ca_file or ca_path is set.

  attr_reader :verify_callback

  ##
  # Sets the depth of SSL certificate verification

  attr_reader :verify_depth

  ##
  # HTTPS verify mode.  Defaults to OpenSSL::SSL::VERIFY_PEER which verifies
  # the server certificate.
  #
  # If no ca_file, ca_path or cert_store is set the default system certificate
  # store is used.
  #
  # You can use +verify_mode+ to override any default values.

  attr_reader :verify_mode

  ##
  # HTTPS verify_hostname.
  #
  # If a client sets this to true and enables SNI with SSLSocket#hostname=,
  # the hostname verification on the server certificate is performed
  # automatically during the handshake using
  # OpenSSL::SSL.verify_certificate_identity().
  #
  # You can set +verify_hostname+ as true to use hostname verification
  # during the handshake.
  #
  # NOTE: This works with Ruby > 3.0.

  attr_reader :verify_hostname

  ##
  # Creates a new Gem::Net::HTTP::Persistent.
  #
  # Set a +name+ for fun.  Your library name should be good enough, but this
  # otherwise has no purpose.
  #
  # +proxy+ may be set to a Gem::URI::HTTP or :ENV to pick up proxy options from
  # the environment.  See proxy_from_env for details.
  #
  # In order to use a Gem::URI for the proxy you may need to do some extra work
  # beyond Gem::URI parsing if the proxy requires a password:
  #
  #   proxy = Gem::URI 'http://proxy.example'
  #   proxy.user     = 'AzureDiamond'
  #   proxy.password = 'hunter2'
  #
  # Set +pool_size+ to limit the maximum number of connections allowed.
  # Defaults to 1/4 the number of allowed file handles or 256 if your OS does
  # not support a limit on allowed file handles.  You can have no more than
  # this many threads with active HTTP transactions.

  def initialize name: nil, proxy: nil, pool_size: DEFAULT_POOL_SIZE
    @name = name

    @debug_output     = nil
    @proxy_uri        = nil
    @no_proxy         = []
    @headers          = {}
    @override_headers = {}
    @http_versions    = {}
    @keep_alive       = 30
    @open_timeout     = nil
    @read_timeout     = nil
    @write_timeout    = nil
    @idle_timeout     = 5
    @max_requests     = nil
    @max_retries      = 1
    @socket_options   = []
    @ssl_generation   = 0 # incremented when SSL session variables change

    @socket_options << [Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1] if
      Socket.const_defined? :TCP_NODELAY

    @pool = Gem::Net::HTTP::Persistent::Pool.new size: pool_size do |http_args|
      Gem::Net::HTTP::Persistent::Connection.new Gem::Net::HTTP, http_args, @ssl_generation
    end

    @certificate        = nil
    @ca_file            = nil
    @ca_path            = nil
    @ciphers            = nil
    @private_key        = nil
    @ssl_timeout        = nil
    @ssl_version        = nil
    @min_version        = nil
    @max_version        = nil
    @verify_callback    = nil
    @verify_depth       = nil
    @verify_mode        = nil
    @verify_hostname    = nil
    @cert_store         = nil

    @generation         = 0 # incremented when proxy Gem::URI changes

    if HAVE_OPENSSL then
      @verify_mode        = OpenSSL::SSL::VERIFY_PEER
      @reuse_ssl_sessions = OpenSSL::SSL.const_defined? :Session
    end

    self.proxy = proxy if proxy
  end

  ##
  # Sets this client's OpenSSL::X509::Certificate

  def certificate= certificate
    @certificate = certificate

    reconnect_ssl
  end

  # For Gem::Net::HTTP parity
  alias cert= certificate=

  ##
  # Sets the SSL certificate authority file.

  def ca_file= file
    @ca_file = file

    reconnect_ssl
  end

  ##
  # Sets the SSL certificate authority path.

  def ca_path= path
    @ca_path = path

    reconnect_ssl
  end

  ##
  # Overrides the default SSL certificate store used for verifying
  # connections.

  def cert_store= store
    @cert_store = store

    reconnect_ssl
  end

  ##
  # The ciphers allowed for SSL connections

  def ciphers= ciphers
    @ciphers = ciphers

    reconnect_ssl
  end

  ##
  # Creates a new connection for +uri+

  def connection_for uri
    use_ssl = uri.scheme.downcase == 'https'

    net_http_args = [uri.hostname, uri.port]

    # I'm unsure if uri.host or uri.hostname should be checked against
    # the proxy bypass list.
    if @proxy_uri and not proxy_bypass? uri.host, uri.port then
      net_http_args.concat @proxy_args
    else
      net_http_args.concat [nil, nil, nil, nil]
    end

    connection = @pool.checkout net_http_args

    http = connection.http

    connection.ressl @ssl_generation if
      connection.ssl_generation != @ssl_generation

    if not http.started? then
      ssl   http if use_ssl
      start http
    elsif expired? connection then
      reset connection
    end

    http.keep_alive_timeout = @idle_timeout  if @idle_timeout
    http.max_retries        = @max_retries   if http.respond_to?(:max_retries=)
    http.read_timeout       = @read_timeout  if @read_timeout
    http.write_timeout      = @write_timeout if
      @write_timeout && http.respond_to?(:write_timeout=)

    return yield connection
  rescue Errno::ECONNREFUSED
    if http.proxy?
      address = http.proxy_address
      port    = http.proxy_port
    else
      address = http.address
      port    = http.port
    end

    raise Error, "connection refused: #{address}:#{port}"
  rescue Errno::EHOSTDOWN
    if http.proxy?
      address = http.proxy_address
      port    = http.proxy_port
    else
      address = http.address
      port    = http.port
    end

    raise Error, "host down: #{address}:#{port}"
  ensure
    @pool.checkin net_http_args
  end

  ##
  # CGI::escape wrapper

  def escape str
    CGI.escape str if str
  end

  ##
  # CGI::unescape wrapper

  def unescape str
    CGI.unescape str if str
  end


  ##
  # Returns true if the connection should be reset due to an idle timeout, or
  # maximum request count, false otherwise.

  def expired? connection
    return true  if     @max_requests && connection.requests >= @max_requests
    return false unless @idle_timeout
    return true  if     @idle_timeout.zero?

    Time.now - connection.last_use > @idle_timeout
  end

  ##
  # Starts the Gem::Net::HTTP +connection+

  def start http
    http.set_debug_output @debug_output if @debug_output
    http.open_timeout = @open_timeout if @open_timeout

    http.start

    socket = http.instance_variable_get :@socket

    if socket then # for fakeweb
      @socket_options.each do |option|
        socket.io.setsockopt(*option)
      end
    end
  end

  ##
  # Finishes the Gem::Net::HTTP +connection+

  def finish connection
    connection.finish

    connection.http.instance_variable_set :@last_communicated, nil
    connection.http.instance_variable_set :@ssl_session, nil unless
      @reuse_ssl_sessions
  end

  ##
  # Returns the HTTP protocol version for +uri+

  def http_version uri
    @http_versions["#{uri.hostname}:#{uri.port}"]
  end

  ##
  # Adds "http://" to the String +uri+ if it is missing.

  def normalize_uri uri
    (uri =~ /^https?:/) ? uri : "http://#{uri}"
  end

  ##
  # Set the maximum number of retries for a request.
  #
  # Defaults to one retry.
  #
  # Set this to 0 to disable retries.

  def max_retries= retries
    retries = retries.to_int

    raise ArgumentError, "max_retries must be positive" if retries < 0

    @max_retries = retries

    reconnect
  end

  ##
  # Sets this client's SSL private key

  def private_key= key
    @private_key = key

    reconnect_ssl
  end

  # For Gem::Net::HTTP parity
  alias key= private_key=

  ##
  # Sets the proxy server.  The +proxy+ may be the Gem::URI of the proxy server,
  # the symbol +:ENV+ which will read the proxy from the environment or nil to
  # disable use of a proxy.  See #proxy_from_env for details on setting the
  # proxy from the environment.
  #
  # If the proxy Gem::URI is set after requests have been made, the next request
  # will shut-down and re-open all connections.
  #
  # The +no_proxy+ query parameter can be used to specify hosts which shouldn't
  # be reached via proxy; if set it should be a comma separated list of
  # hostname suffixes, optionally with +:port+ appended, for example
  # <tt>example.com,some.host:8080</tt>.

  def proxy= proxy
    @proxy_uri = case proxy
                 when :ENV      then proxy_from_env
                 when Gem::URI::HTTP then proxy
                 when nil       then # ignore
                 else raise ArgumentError, 'proxy must be :ENV or a Gem::URI::HTTP'
                 end

    @no_proxy.clear

    if @proxy_uri then
      @proxy_args = [
        @proxy_uri.hostname,
        @proxy_uri.port,
        unescape(@proxy_uri.user),
        unescape(@proxy_uri.password),
      ]

      @proxy_connection_id = [nil, *@proxy_args].join ':'

      if @proxy_uri.query then
        @no_proxy = CGI.parse(@proxy_uri.query)['no_proxy'].join(',').downcase.split(',').map { |x| x.strip }.reject { |x| x.empty? }
      end
    end

    reconnect
    reconnect_ssl
  end

  ##
  # Creates a Gem::URI for an HTTP proxy server from ENV variables.
  #
  # If +HTTP_PROXY+ is set a proxy will be returned.
  #
  # If +HTTP_PROXY_USER+ or +HTTP_PROXY_PASS+ are set the Gem::URI is given the
  # indicated user and password unless HTTP_PROXY contains either of these in
  # the Gem::URI.
  #
  # The +NO_PROXY+ ENV variable can be used to specify hosts which shouldn't
  # be reached via proxy; if set it should be a comma separated list of
  # hostname suffixes, optionally with +:port+ appended, for example
  # <tt>example.com,some.host:8080</tt>. When set to <tt>*</tt> no proxy will
  # be returned.
  #
  # For Windows users, lowercase ENV variables are preferred over uppercase ENV
  # variables.

  def proxy_from_env
    env_proxy = ENV['http_proxy'] || ENV['HTTP_PROXY']

    return nil if env_proxy.nil? or env_proxy.empty?

    uri = Gem::URI normalize_uri env_proxy

    env_no_proxy = ENV['no_proxy'] || ENV['NO_PROXY']

    # '*' is special case for always bypass
    return nil if env_no_proxy == '*'

    if env_no_proxy then
      uri.query = "no_proxy=#{escape(env_no_proxy)}"
    end

    unless uri.user or uri.password then
      uri.user     = escape ENV['http_proxy_user'] || ENV['HTTP_PROXY_USER']
      uri.password = escape ENV['http_proxy_pass'] || ENV['HTTP_PROXY_PASS']
    end

    uri
  end

  ##
  # Returns true when proxy should by bypassed for host.

  def proxy_bypass? host, port
    host = host.downcase
    host_port = [host, port].join ':'

    @no_proxy.each do |name|
      return true if host[-name.length, name.length] == name or
         host_port[-name.length, name.length] == name
    end

    false
  end

  ##
  # Forces reconnection of all HTTP connections, including TLS/SSL
  # connections.

  def reconnect
    @generation += 1
  end

  ##
  # Forces reconnection of only TLS/SSL connections.

  def reconnect_ssl
    @ssl_generation += 1
  end

  ##
  # Finishes then restarts the Gem::Net::HTTP +connection+

  def reset connection
    http = connection.http

    finish connection

    start http
  rescue Errno::ECONNREFUSED
    e = Error.new "connection refused: #{http.address}:#{http.port}"
    e.set_backtrace $@
    raise e
  rescue Errno::EHOSTDOWN
    e = Error.new "host down: #{http.address}:#{http.port}"
    e.set_backtrace $@
    raise e
  end

  ##
  # Makes a request on +uri+.  If +req+ is nil a Gem::Net::HTTP::Get is performed
  # against +uri+.
  #
  # If a block is passed #request behaves like Gem::Net::HTTP#request (the body of
  # the response will not have been read).
  #
  # +req+ must be a Gem::Net::HTTPGenericRequest subclass (see Gem::Net::HTTP for a list).

  def request uri, req = nil, &block
    uri      = Gem::URI uri
    req      = request_setup req || uri
    response = nil

    connection_for uri do |connection|
      http = connection.http

      begin
        connection.requests += 1

        response = http.request req, &block

        if req.connection_close? or
          (response.http_version <= '1.0' and
            not response.connection_keep_alive?) or
            response.connection_close? then
          finish connection
        end
      rescue Exception # make sure to close the connection when it was interrupted
        finish connection

        raise
      ensure
        connection.last_use = Time.now
      end
    end

    @http_versions["#{uri.hostname}:#{uri.port}"] ||= response.http_version

    response
  end

  ##
  # Creates a GET request if +req_or_uri+ is a Gem::URI and adds headers to the
  # request.
  #
  # Returns the request.

  def request_setup req_or_uri # :nodoc:
    req = if req_or_uri.respond_to? 'request_uri' then
            Gem::Net::HTTP::Get.new req_or_uri.request_uri
          else
            req_or_uri
          end

    @headers.each do |pair|
      req.add_field(*pair)
    end

    @override_headers.each do |name, value|
      req[name] = value
    end

    unless req['Connection'] then
      req.add_field 'Connection', 'keep-alive'
      req.add_field 'Keep-Alive', @keep_alive
    end

    req
  end

  ##
  # Shuts down all connections
  #
  # *NOTE*: Calling shutdown for can be dangerous!
  #
  # If any thread is still using a connection it may cause an error!  Call
  # #shutdown when you are completely done making requests!

  def shutdown
    @pool.shutdown { |http| http.finish }
  end

  ##
  # Enables SSL on +connection+

  def ssl connection
    connection.use_ssl = true

    connection.ciphers     = @ciphers     if @ciphers
    connection.ssl_timeout = @ssl_timeout if @ssl_timeout
    connection.ssl_version = @ssl_version if @ssl_version
    connection.min_version = @min_version if @min_version
    connection.max_version = @max_version if @max_version

    connection.verify_depth    = @verify_depth
    connection.verify_mode     = @verify_mode
    connection.verify_hostname = @verify_hostname if
      @verify_hostname != nil && connection.respond_to?(:verify_hostname=)

    if OpenSSL::SSL::VERIFY_PEER == OpenSSL::SSL::VERIFY_NONE and
       not Object.const_defined?(:I_KNOW_THAT_OPENSSL_VERIFY_PEER_EQUALS_VERIFY_NONE_IS_WRONG) then
      warn <<-WARNING
                             !!!SECURITY WARNING!!!

The SSL HTTP connection to:

  #{connection.address}:#{connection.port}

                           !!!MAY NOT BE VERIFIED!!!

On your platform your OpenSSL implementation is broken.

There is no difference between the values of VERIFY_NONE and VERIFY_PEER.

This means that attempting to verify the security of SSL connections may not
work.  This exposes you to man-in-the-middle exploits, snooping on the
contents of your connection and other dangers to the security of your data.

To disable this warning define the following constant at top-level in your
application:

  I_KNOW_THAT_OPENSSL_VERIFY_PEER_EQUALS_VERIFY_NONE_IS_WRONG = nil

      WARNING
    end

    connection.ca_file = @ca_file if @ca_file
    connection.ca_path = @ca_path if @ca_path

    if @ca_file or @ca_path then
      connection.verify_mode = OpenSSL::SSL::VERIFY_PEER
      connection.verify_callback = @verify_callback if @verify_callback
    end

    if @certificate and @private_key then
      connection.cert = @certificate
      connection.key  = @private_key
    end

    connection.cert_store = if @cert_store then
                              @cert_store
                            else
                              store = OpenSSL::X509::Store.new
                              store.set_default_paths
                              store
                            end
  end

  ##
  # SSL session lifetime

  def ssl_timeout= ssl_timeout
    @ssl_timeout = ssl_timeout

    reconnect_ssl
  end

  ##
  # SSL version to use

  def ssl_version= ssl_version
    @ssl_version = ssl_version

    reconnect_ssl
  end

  ##
  # Minimum SSL version to use

  def min_version= min_version
    @min_version = min_version

    reconnect_ssl
  end

  ##
  # maximum SSL version to use

  def max_version= max_version
    @max_version = max_version

    reconnect_ssl
  end

  ##
  # Sets the depth of SSL certificate verification

  def verify_depth= verify_depth
    @verify_depth = verify_depth

    reconnect_ssl
  end

  ##
  # Sets the HTTPS verify mode.  Defaults to OpenSSL::SSL::VERIFY_PEER.
  #
  # Setting this to VERIFY_NONE is a VERY BAD IDEA and should NEVER be used.
  # Securely transfer the correct certificate and update the default
  # certificate store or set the ca file instead.

  def verify_mode= verify_mode
    @verify_mode = verify_mode

    reconnect_ssl
  end

  ##
  # Sets the HTTPS verify_hostname.

  def verify_hostname= verify_hostname
    @verify_hostname = verify_hostname

    reconnect_ssl
  end

  ##
  # SSL verification callback.

  def verify_callback= callback
    @verify_callback = callback

    reconnect_ssl
  end
end

require_relative 'persistent/connection'
require_relative 'persistent/pool'
