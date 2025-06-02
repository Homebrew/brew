# frozen_string_literal: true

require_relative "../rubygems"
require_relative "request"
require_relative "request/connection_pools"
require_relative "s3_uri_signer"
require_relative "uri_formatter"
require_relative "uri"
require_relative "user_interaction"

##
# RemoteFetcher handles the details of fetching gems and gem information from
# a remote source.

class Gem::RemoteFetcher
  include Gem::UserInteraction

  ##
  # A FetchError exception wraps up the various possible IO and HTTP failures
  # that could happen while downloading from the internet.

  class FetchError < Gem::Exception
    ##
    # The URI which was being accessed when the exception happened.

    attr_accessor :uri, :original_uri

    def initialize(message, uri)
      uri = Gem::Uri.new(uri)

      super uri.redact_credentials_from(message)

      @original_uri = uri.to_s
      @uri = uri.redacted.to_s
    end

    def to_s # :nodoc:
      "#{super} (#{uri})"
    end
  end

  ##
  # A FetchError that indicates that the reason for not being
  # able to fetch data was that the host could not be contacted

  class UnknownHostError < FetchError
  end
  deprecate_constant(:UnknownHostError)

  @fetcher = nil

  ##
  # Cached RemoteFetcher instance.

  def self.fetcher
    @fetcher ||= new Gem.configuration[:http_proxy]
  end

  attr_accessor :headers

  ##
  # Initialize a remote fetcher using the source URI and possible proxy
  # information.
  #
  # +proxy+
  # * [String]: explicit specification of proxy; overrides any environment
  #             variable setting
  # * nil: respect environment variables (HTTP_PROXY, HTTP_PROXY_USER,
  #        HTTP_PROXY_PASS)
  # * <tt>:no_proxy</tt>: ignore environment variables and _don't_ use a proxy
  #
  # +headers+: A set of additional HTTP headers to be sent to the server when
  #            fetching the gem.

  def initialize(proxy=nil, dns=nil, headers={})
    require_relative "core_ext/tcpsocket_init" if Gem.configuration.ipv4_fallback_enabled
    require_relative "vendored_net_http"
    require_relative "vendor/uri/lib/uri"

    Socket.do_not_reverse_lookup = true

    @proxy = proxy
    @pools = {}
    @pool_lock = Thread::Mutex.new
    @cert_files = Gem::Request.get_cert_files

    @headers = headers
  end

  ##
  # Given a name and requirement, downloads this gem into cache and returns the
  # filename. Returns nil if the gem cannot be located.
  #--
  # Should probably be integrated with #download below, but that will be a
  # larger, more encompassing effort. -erikh

  def download_to_cache(dependency)
    found, _ = Gem::SpecFetcher.fetcher.spec_for_dependency dependency

    return if found.empty?

    spec, source = found.max_by {|(s,_)| s.version }

    download spec, source.uri
  end

  ##
  # Moves the gem +spec+ from +source_uri+ to the cache dir unless it is
  # already there.  If the source_uri is local the gem cache dir copy is
  # always replaced.

  def download(spec, source_uri, install_dir = Gem.dir)
    install_cache_dir = File.join install_dir, "cache"
    cache_dir =
      if Dir.pwd == install_dir # see fetch_command
        install_dir
      elsif File.writable?(install_cache_dir) || (File.writable?(install_dir) && !File.exist?(install_cache_dir))
        install_cache_dir
      else
        File.join Gem.user_dir, "cache"
      end

    gem_file_name = File.basename spec.cache_file
    local_gem_path = File.join cache_dir, gem_file_name

    require "fileutils"
    begin
      FileUtils.mkdir_p cache_dir
    rescue StandardError
      nil
    end unless File.exist? cache_dir

    source_uri = Gem::Uri.new(source_uri)

    scheme = source_uri.scheme

    # Gem::URI.parse gets confused by MS Windows paths with forward slashes.
    scheme = nil if /^[a-z]$/i.match?(scheme)

    # REFACTOR: split this up and dispatch on scheme (eg download_http)
    # REFACTOR: be sure to clean up fake fetcher when you do this... cleaner
    case scheme
    when "http", "https", "s3" then
      unless File.exist? local_gem_path
        begin
          verbose "Downloading gem #{gem_file_name}"

          remote_gem_path = source_uri + "gems/#{gem_file_name}"

          cache_update_path remote_gem_path, local_gem_path
        rescue FetchError
          raise if spec.original_platform == spec.platform

          alternate_name = "#{spec.original_name}.gem"

          verbose "Failed, downloading gem #{alternate_name}"

          remote_gem_path = source_uri + "gems/#{alternate_name}"

          cache_update_path remote_gem_path, local_gem_path
        end
      end
    when "file" then
      begin
        path = source_uri.path
        path = File.dirname(path) if File.extname(path) == ".gem"

        remote_gem_path = Gem::Util.correct_for_windows_path(File.join(path, "gems", gem_file_name))

        FileUtils.cp(remote_gem_path, local_gem_path)
      rescue Errno::EACCES
        local_gem_path = source_uri.to_s
      end

      verbose "Using local gem #{local_gem_path}"
    when nil then # TODO: test for local overriding cache
      source_path = if Gem.win_platform? && source_uri.scheme &&
                       !source_uri.path.include?(":")
        "#{source_uri.scheme}:#{source_uri.path}"
      else
        source_uri.path
      end

      source_path = Gem::UriFormatter.new(source_path).unescape

      begin
        FileUtils.cp source_path, local_gem_path unless
          File.identical?(source_path, local_gem_path)
      rescue Errno::EACCES
        local_gem_path = source_uri.to_s
      end

      verbose "Using local gem #{local_gem_path}"
    else
      raise ArgumentError, "unsupported URI scheme #{source_uri.scheme}"
    end

    local_gem_path
  end

  ##
  # File Fetcher. Dispatched by +fetch_path+. Use it instead.

  def fetch_file(uri, *_)
    Gem.read_binary Gem::Util.correct_for_windows_path uri.path
  end

  ##
  # HTTP Fetcher. Dispatched by +fetch_path+. Use it instead.

  def fetch_http(uri, last_modified = nil, head = false, depth = 0)
    fetch_type = head ? Gem::Net::HTTP::Head : Gem::Net::HTTP::Get
    response   = request uri, fetch_type, last_modified do |req|
      headers.each {|k,v| req.add_field(k,v) }
    end

    case response
    when Gem::Net::HTTPOK, Gem::Net::HTTPNotModified then
      response.uri = uri
      head ? response : response.body
    when Gem::Net::HTTPMovedPermanently, Gem::Net::HTTPFound, Gem::Net::HTTPSeeOther,
         Gem::Net::HTTPTemporaryRedirect then
      raise FetchError.new("too many redirects", uri) if depth > 10

      unless location = response["Location"]
        raise FetchError.new("redirecting but no redirect location was given", uri)
      end
      location = Gem::Uri.new location

      if https?(uri) && !https?(location)
        raise FetchError.new("redirecting to non-https resource: #{location}", uri)
      end

      fetch_http(location, last_modified, head, depth + 1)
    else
      raise FetchError.new("bad response #{response.message} #{response.code}", uri)
    end
  end

  alias_method :fetch_https, :fetch_http

  ##
  # Downloads +uri+ and returns it as a String.

  def fetch_path(uri, mtime = nil, head = false)
    uri = Gem::Uri.new uri

    unless uri.scheme
      raise ArgumentError, "uri scheme is invalid: #{uri.scheme.inspect}"
    end

    data = send "fetch_#{uri.scheme}", uri, mtime, head

    if data && !head && uri.to_s.end_with?(".gz")
      begin
        data = Gem::Util.gunzip data
      rescue Zlib::GzipFile::Error
        raise FetchError.new("server did not return a valid file", uri)
      end
    end

    data
  rescue Gem::Timeout::Error, IOError, SocketError, SystemCallError,
         *(OpenSSL::SSL::SSLError if Gem::HAVE_OPENSSL) => e
    raise FetchError.new("#{e.class}: #{e}", uri)
  end

  def fetch_s3(uri, mtime = nil, head = false)
    begin
      public_uri = s3_uri_signer(uri).sign
    rescue Gem::S3URISigner::ConfigurationError, Gem::S3URISigner::InstanceProfileError => e
      raise FetchError.new(e.message, "s3://#{uri.host}")
    end
    fetch_https public_uri, mtime, head
  end

  # we have our own signing code here to avoid a dependency on the aws-sdk gem
  def s3_uri_signer(uri)
    Gem::S3URISigner.new(uri)
  end

  ##
  # Downloads +uri+ to +path+ if necessary. If no path is given, it just
  # passes the data.

  def cache_update_path(uri, path = nil, update = true)
    mtime = begin
              path && File.stat(path).mtime
            rescue StandardError
              nil
            end

    data = fetch_path(uri, mtime)

    if data.nil? # indicates the server returned 304 Not Modified
      return Gem.read_binary(path)
    end

    if update && path
      Gem.write_binary(path, data)
    end

    data
  end

  ##
  # Performs a Gem::Net::HTTP request of type +request_class+ on +uri+ returning
  # a Gem::Net::HTTP response object.  request maintains a table of persistent
  # connections to reduce connect overhead.

  def request(uri, request_class, last_modified = nil)
    proxy = proxy_for @proxy, uri
    pool  = pools_for(proxy).pool_for uri

    request = Gem::Request.new uri, request_class, last_modified, pool

    request.fetch do |req|
      yield req if block_given?
    end
  end

  def https?(uri)
    uri.scheme.casecmp("https").zero?
  end

  def close_all
    @pools.each_value(&:close_all)
  end

  private

  def proxy_for(proxy, uri)
    Gem::Request.proxy_uri(proxy || Gem::Request.get_proxy_from_env(uri.scheme))
  end

  def pools_for(proxy)
    @pool_lock.synchronize do
      @pools[proxy] ||= Gem::Request::ConnectionPools.new proxy, @cert_files
    end
  end
end
