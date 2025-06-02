# frozen_string_literal: true

require_relative "vendored_persistent"
require "cgi"
require "securerandom"
require "zlib"
require "rubygems/request"

module Bundler
  # Handles all the fetching with the rubygems server
  class Fetcher
    autoload :CompactIndex, File.expand_path("fetcher/compact_index", __dir__)
    autoload :Downloader, File.expand_path("fetcher/downloader", __dir__)
    autoload :Dependency, File.expand_path("fetcher/dependency", __dir__)
    autoload :Index, File.expand_path("fetcher/index", __dir__)

    # This error is raised when it looks like the network is down
    class NetworkDownError < HTTPError; end
    # This error is raised if we should rate limit our requests to the API
    class TooManyRequestsError < HTTPError; end
    # This error is raised if the API returns a 413 (only printed in verbose)
    class FallbackError < HTTPError; end

    # This is the error raised if OpenSSL fails the cert verification
    class CertificateFailureError < HTTPError
      def initialize(remote_uri)
        remote_uri = filter_uri(remote_uri)
        super "Could not verify the SSL certificate for #{remote_uri}.\nThere" \
          " is a chance you are experiencing a man-in-the-middle attack, but" \
          " most likely your system doesn't have the CA certificates needed" \
          " for verification. For information about OpenSSL certificates, see" \
          " https://railsapps.github.io/openssl-certificate-verify-failed.html." \
          " To connect without using SSL, edit your Gemfile" \
          " sources and change 'https' to 'http'."
      end
    end

    # This is the error raised when a source is HTTPS and OpenSSL didn't load
    class SSLError < HTTPError
      def initialize(msg = nil)
        super msg || "Could not load OpenSSL.\n" \
            "You must recompile Ruby with OpenSSL support or change the sources in your " \
            "Gemfile from 'https' to 'http'. Instructions for compiling with OpenSSL " \
            "using RVM are available at rvm.io/packages/openssl."
      end
    end

    # This error is raised if HTTP authentication is required, but not provided.
    class AuthenticationRequiredError < HTTPError
      def initialize(remote_uri)
        remote_uri = filter_uri(remote_uri)
        super "Authentication is required for #{remote_uri}.\n" \
          "Please supply credentials for this source. You can do this by running:\n" \
          "`bundle config set --global #{remote_uri} username:password`\n" \
          "or by storing the credentials in the `#{Settings.key_for(remote_uri)}` environment variable"
      end
    end

    # This error is raised if HTTP authentication is provided, but incorrect.
    class BadAuthenticationError < HTTPError
      def initialize(remote_uri)
        remote_uri = filter_uri(remote_uri)
        super "Bad username or password for #{remote_uri}.\n" \
          "Please double-check your credentials and correct them."
      end
    end

    # Exceptions classes that should bypass retry attempts. If your password didn't work the
    # first time, it's not going to the third time.
    NET_ERRORS = [:HTTPBadGateway, :HTTPBadRequest, :HTTPFailedDependency,
                  :HTTPForbidden, :HTTPInsufficientStorage, :HTTPMethodNotAllowed,
                  :HTTPMovedPermanently, :HTTPNoContent, :HTTPNotFound,
                  :HTTPNotImplemented, :HTTPPreconditionFailed, :HTTPRequestEntityTooLarge,
                  :HTTPRequestURITooLong, :HTTPUnauthorized, :HTTPUnprocessableEntity,
                  :HTTPUnsupportedMediaType, :HTTPVersionNotSupported].freeze
    FAIL_ERRORS = begin
      fail_errors = [AuthenticationRequiredError, BadAuthenticationError, FallbackError]
      fail_errors << Gem::Requirement::BadRequirementError
      fail_errors.concat(NET_ERRORS.map {|e| Net.const_get(e) })
    end.freeze

    class << self
      attr_accessor :disable_endpoint, :api_timeout, :redirect_limit, :max_retries
    end

    self.redirect_limit = Bundler.settings[:redirect] # How many redirects to allow in one request
    self.api_timeout    = Bundler.settings[:timeout] # How long to wait for each API call
    self.max_retries    = Bundler.settings[:retry] # How many retries for the API call

    def initialize(remote)
      @remote = remote

      Socket.do_not_reverse_lookup = true
      connection # create persistent connection
    end

    def uri
      @remote.anonymized_uri
    end

    # fetch a gem specification
    def fetch_spec(spec)
      spec -= [nil, "ruby", ""]
      spec_file_name = "#{spec.join "-"}.gemspec"

      uri = Bundler::URI.parse("#{remote_uri}#{Gem::MARSHAL_SPEC_DIR}#{spec_file_name}.rz")
      if uri.scheme == "file"
        path = Bundler.rubygems.correct_for_windows_path(uri.path)
        Bundler.load_marshal Bundler.rubygems.inflate(Gem.read_binary(path))
      elsif cached_spec_path = gemspec_cached_path(spec_file_name)
        Bundler.load_gemspec(cached_spec_path)
      else
        Bundler.load_marshal Bundler.rubygems.inflate(downloader.fetch(uri).body)
      end
    rescue MarshalError
      raise HTTPError, "Gemspec #{spec} contained invalid data.\n" \
        "Your network or your gem server is probably having issues right now."
    end

    # return the specs in the bundler format as an index with retries
    def specs_with_retry(gem_names, source)
      Bundler::Retry.new("fetcher", FAIL_ERRORS).attempts do
        specs(gem_names, source)
      end
    end

    # return the specs in the bundler format as an index
    def specs(gem_names, source)
      index = Bundler::Index.new

      if Bundler::Fetcher.disable_endpoint
        @use_api = false
        specs = fetchers.last.specs(gem_names)
      else
        specs = []
        @fetchers = fetchers.drop_while do |f|
          !f.available? || (f.api_fetcher? && !gem_names) || !specs = f.specs(gem_names)
        end
        @use_api = false if fetchers.none?(&:api_fetcher?)
      end

      specs.each do |name, version, platform, dependencies, metadata|
        spec = if dependencies
          EndpointSpecification.new(name, version, platform, self, dependencies, metadata)
        else
          RemoteSpecification.new(name, version, platform, self)
        end
        spec.source = source
        spec.remote = @remote
        index << spec
      end

      index
    rescue CertificateFailureError
      Bundler.ui.info "" if gem_names && use_api # newline after dots
      raise
    end

    def use_api
      return @use_api if defined?(@use_api)

      fetchers.shift until fetchers.first.available?

      @use_api = if remote_uri.scheme == "file" || Bundler::Fetcher.disable_endpoint
        false
      else
        fetchers.first.api_fetcher?
      end
    end

    def user_agent
      @user_agent ||= begin
        ruby = Bundler::RubyVersion.system

        agent = String.new("bundler/#{Bundler::VERSION}")
        agent << " rubygems/#{Gem::VERSION}"
        agent << " ruby/#{ruby.versions_string(ruby.versions)}"
        agent << " (#{ruby.host})"
        agent << " command/#{ARGV.first}"

        if ruby.engine != "ruby"
          # engine_version raises on unknown engines
          engine_version = begin
                             ruby.engine_versions
                           rescue RuntimeError
                             "???"
                           end
          agent << " #{ruby.engine}/#{ruby.versions_string(engine_version)}"
        end

        agent << " options/#{Bundler.settings.all.join(",")}"

        agent << " ci/#{cis.join(",")}" if cis.any?

        # add a random ID so we can consolidate runs server-side
        agent << " " << SecureRandom.hex(8)

        # add any user agent strings set in the config
        extra_ua = Bundler.settings[:user_agent]
        agent << " " << extra_ua if extra_ua

        agent
      end
    end

    def fetchers
      @fetchers ||= FETCHERS.map {|f| f.new(downloader, @remote, uri) }
    end

    def http_proxy
      return unless uri = connection.proxy_uri
      uri.to_s
    end

    def inspect
      "#<#{self.class}:0x#{object_id} uri=#{uri}>"
    end

    private

    FETCHERS = [CompactIndex, Dependency, Index].freeze

    def cis
      env_cis = {
        "TRAVIS" => "travis",
        "CIRCLECI" => "circle",
        "SEMAPHORE" => "semaphore",
        "JENKINS_URL" => "jenkins",
        "BUILDBOX" => "buildbox",
        "GO_SERVER_URL" => "go",
        "SNAP_CI" => "snap",
        "GITLAB_CI" => "gitlab",
        "GITHUB_ACTIONS" => "github",
        "CI_NAME" => ENV["CI_NAME"],
        "CI" => "ci",
      }
      env_cis.find_all {|env, _| ENV[env] }.map {|_, ci| ci }
    end

    def connection
      @connection ||= begin
        needs_ssl = remote_uri.scheme == "https" ||
                    Bundler.settings[:ssl_verify_mode] ||
                    Bundler.settings[:ssl_client_cert]
        raise SSLError if needs_ssl && !defined?(OpenSSL::SSL)

        con = PersistentHTTP.new :name => "bundler", :proxy => :ENV
        if gem_proxy = Gem.configuration[:http_proxy]
          con.proxy = Bundler::URI.parse(gem_proxy) if gem_proxy != :no_proxy
        end

        if remote_uri.scheme == "https"
          con.verify_mode = (Bundler.settings[:ssl_verify_mode] ||
            OpenSSL::SSL::VERIFY_PEER)
          con.cert_store = bundler_cert_store
        end

        ssl_client_cert = Bundler.settings[:ssl_client_cert] ||
                          (Gem.configuration.ssl_client_cert if
                            Gem.configuration.respond_to?(:ssl_client_cert))
        if ssl_client_cert
          pem = File.read(ssl_client_cert)
          con.cert = OpenSSL::X509::Certificate.new(pem)
          con.key  = OpenSSL::PKey::RSA.new(pem)
        end

        con.read_timeout = Fetcher.api_timeout
        con.open_timeout = Fetcher.api_timeout
        con.override_headers["User-Agent"] = user_agent
        con.override_headers["X-Gemfile-Source"] = @remote.original_uri.to_s if @remote.original_uri
        con
      end
    end

    # cached gem specification path, if one exists
    def gemspec_cached_path(spec_file_name)
      paths = Bundler.rubygems.spec_cache_dirs.map {|dir| File.join(dir, spec_file_name) }
      paths.find {|path| File.file? path }
    end

    HTTP_ERRORS = [
      Timeout::Error, EOFError, SocketError, Errno::ENETDOWN, Errno::ENETUNREACH,
      Errno::EINVAL, Errno::ECONNRESET, Errno::ETIMEDOUT, Errno::EAGAIN,
      Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError,
      PersistentHTTP::Error, Zlib::BufError, Errno::EHOSTUNREACH
    ].freeze

    def bundler_cert_store
      store = OpenSSL::X509::Store.new
      ssl_ca_cert = Bundler.settings[:ssl_ca_cert] ||
                    (Gem.configuration.ssl_ca_cert if
                      Gem.configuration.respond_to?(:ssl_ca_cert))
      if ssl_ca_cert
        if File.directory? ssl_ca_cert
          store.add_path ssl_ca_cert
        else
          store.add_file ssl_ca_cert
        end
      else
        store.set_default_paths
        Gem::Request.get_cert_files.each {|c| store.add_file c }
      end
      store
    end

    def remote_uri
      @remote.uri
    end

    def downloader
      @downloader ||= Downloader.new(connection, self.class.redirect_limit)
    end
  end
end
