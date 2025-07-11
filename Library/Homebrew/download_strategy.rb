# typed: strict
# frozen_string_literal: true

require "json"
require "time"
require "unpack_strategy"
require "lazy_object"
require "lock_file"
require "system_command"

# Need to define this before requiring Mechanize to avoid:
#   uninitialized constant Mechanize
# rubocop:disable Lint/EmptyClass
class Mechanize; end
require "vendor/gems/mechanize/lib/mechanize/http/content_disposition_parser"
# rubocop:enable Lint/EmptyClass

require "utils/curl"
require "utils/github"
require "utils/timer"

require "github_packages"

# @abstract Abstract superclass for all download strategies.
class AbstractDownloadStrategy
  extend T::Helpers
  include FileUtils
  include Context
  include SystemCommand::Mixin

  abstract!

  # Extension for bottle downloads.
  module Pourable
    extend T::Helpers

    requires_ancestor { AbstractDownloadStrategy }

    sig { params(block: T.nilable(T.proc.params(arg0: String).returns(T.anything))).returns(T.nilable(T.anything)) }
    def stage(&block)
      ohai "Pouring #{basename}"
      super
    end
  end

  # The download URL.
  #
  # @api public
  sig { returns(String) }
  attr_reader :url

  sig { returns(Pathname) }
  attr_reader :cache

  sig { returns(T::Hash[Symbol, T.untyped]) }
  attr_reader :meta

  sig { returns(String) }
  attr_reader :name

  sig { returns(T.any(NilClass, String, Version)) }
  attr_reader :version

  private :meta, :name, :version

  sig { params(url: String, name: String, version: T.any(NilClass, String, Version), meta: T.untyped).void }
  def initialize(url, name, version, **meta)
    @cached_location = T.let(nil, T.nilable(Pathname))
    @ref_type = T.let(nil, T.nilable(Symbol))
    @ref = T.let(nil, T.untyped)
    @url = url
    @name = name
    @version = version
    @cache = T.let(meta.fetch(:cache, HOMEBREW_CACHE), Pathname)
    @meta = T.let(meta, T::Hash[Symbol, T.untyped])
    @quiet = T.let(false, T.nilable(T::Boolean))
    extend Pourable if meta[:bottle]
  end

  # Download and cache the resource at {#cached_location}.
  #
  # @api public
  sig { overridable.params(timeout: T.any(Float, Integer, NilClass)).void }
  def fetch(timeout: nil); end

  # Location of the cached download.
  #
  # @api public
  sig { abstract.returns(Pathname) }
  def cached_location; end

  # Disable any output during downloading.
  #
  # @api public
  sig { void }
  def quiet!
    @quiet = T.let(true, T.nilable(T::Boolean))
  end

  sig { returns(T::Boolean) }
  def quiet?
    Context.current.quiet? || @quiet || false
  end

  # Unpack {#cached_location} into the current working directory.
  #
  # Additionally, if a block is given, the working directory was previously empty
  # and a single directory is extracted from the archive, the block will be called
  # with the working directory changed to that directory. Otherwise this method
  # will return, or the block will be called, without changing the current working
  # directory.
  #
  # @api public
  sig { overridable.params(block: T.untyped).void }
  def stage(&block)
    UnpackStrategy.detect(cached_location,
                          prioritize_extension: true,
                          ref_type: @ref_type, ref: @ref)
                  .extract_nestedly(basename:,
                                    prioritize_extension: true,
                                    verbose:              verbose? && !quiet?)
    chdir(&block) if block
  end

  sig { params(block: T.untyped).void }
  def chdir(&block)
    entries = Dir["*"]
    raise "Empty archive" if entries.empty?

    if entries.length != 1
      yield
      return
    end

    if File.directory? entries.fetch(0)
      Dir.chdir(entries.fetch(0), &block)
    else
      yield
    end
  end
  private :chdir

  # Returns the most recent modified time for all files in the current working directory after stage.
  #
  # @api public
  sig { overridable.returns(Time) }
  def source_modified_time
    Pathname.pwd.to_enum(:find).select(&:file?).map(&:mtime).max
  end

  # Remove {#cached_location} and any other files associated with the resource
  # from the cache.
  #
  # @api public
  sig { overridable.void }
  def clear_cache
    rm_rf(cached_location)
  end

  sig { returns(Pathname) }
  def basename
    cached_location.basename
  end

  private

  sig { params(args: T.anything).void }
  def puts(*args)
    super unless quiet?
  end

  sig { params(args: T.anything).void }
  def ohai(*args)
    super unless quiet?
  end

  sig { params(args: String, options: T.untyped).returns(SystemCommand::Result) }
  def silent_command(*args, **options)
    system_command(*args, print_stderr: false, env:, **options)
  end

  sig { params(args: String, options: T.untyped).returns(SystemCommand::Result) }
  def command!(*args, **options)
    system_command!(
      *args,
      env: env.merge(options.fetch(:env, {})),
      **command_output_options,
      **options,
    )
  end

  sig { returns(T::Hash[Symbol, T::Boolean]) }
  def command_output_options
    {
      print_stdout: !quiet?,
      print_stderr: !quiet?,
      verbose:      verbose? && !quiet?,
    }
  end

  sig { overridable.returns(T::Hash[String, String]) }
  def env
    {}
  end
end

# @abstract Abstract superclass for all download strategies downloading from a version control system.
class VCSDownloadStrategy < AbstractDownloadStrategy
  abstract!

  sig { override.returns(Pathname) }
  attr_reader :cached_location

  REF_TYPES = [:tag, :branch, :revisions, :revision].freeze

  sig { params(url: String, name: String, version: T.any(NilClass, String, Version), meta: T.untyped).void }
  def initialize(url, name, version, **meta)
    super
    extracted_ref = extract_ref(meta)
    @ref_type = T.let(extracted_ref.fetch(0), T.nilable(Symbol))
    @ref = T.let(extracted_ref.fetch(1), T.untyped)
    @revision = T.let(meta[:revision], T.nilable(String))
    @cached_location = T.let(@cache/Utils.safe_filename("#{name}--#{cache_tag}"), Pathname)
  end

  # Download and cache the repository at {#cached_location}.
  #
  # @api public
  sig { override.params(timeout: T.any(Float, Integer, NilClass)).void }
  def fetch(timeout: nil)
    end_time = Time.now + timeout if timeout

    ohai "Cloning #{url}"

    if cached_location.exist? && repo_valid?
      puts "Updating #{cached_location}"
      update(timeout: end_time)
    elsif cached_location.exist?
      puts "Removing invalid repository from cache"
      clear_cache
      clone_repo(timeout: end_time)
    else
      clone_repo(timeout: end_time)
    end

    v = version
    v.update_commit(last_commit) if v.is_a?(Version) && head?

    return if @ref_type != :tag || @revision.blank? || current_revision.blank? || current_revision == @revision

    raise <<~EOS
      #{@ref} tag should be #{@revision}
      but is actually #{current_revision}
    EOS
  end

  sig { returns(String) }
  def fetch_last_commit
    fetch
    last_commit
  end

  sig { overridable.params(commit: T.nilable(String)).returns(T::Boolean) }
  def commit_outdated?(commit)
    @last_commit ||= T.let(fetch_last_commit, T.nilable(String))
    commit != @last_commit
  end

  sig { returns(T::Boolean) }
  def head?
    v = version
    v.is_a?(Version) ? v.head? : false
  end

  # Return the most recent modified timestamp.
  #
  # @api public
  sig { overridable.returns(String) }
  def last_commit
    source_modified_time.to_i.to_s
  end

  private

  sig { abstract.returns(String) }
  def cache_tag; end

  sig { abstract.returns(T::Boolean) }
  def repo_valid?; end

  sig { abstract.params(timeout: T.nilable(Time)).void }
  def clone_repo(timeout: nil); end

  sig { abstract.params(timeout: T.nilable(Time)).void }
  def update(timeout: nil); end

  sig { overridable.returns(T.nilable(String)) }
  def current_revision; end

  sig { params(specs: T::Hash[T.nilable(Symbol), T.untyped]).returns([T.nilable(Symbol), T.untyped]) }
  def extract_ref(specs)
    key = REF_TYPES.find { |type| specs.key?(type) }
    [key, specs[key]]
  end
end

# @abstract Abstract superclass for all download strategies downloading a single file.
class AbstractFileDownloadStrategy < AbstractDownloadStrategy
  abstract!

  # Path for storing an incomplete download while the download is still in progress.
  #
  # @api public
  sig { returns(Pathname) }
  def temporary_path
    @temporary_path ||= T.let(Pathname.new("#{cached_location}.incomplete"), T.nilable(Pathname))
  end

  # Path of the symlink (whose name includes the resource name, version and extension)
  # pointing to {#cached_location}.
  #
  # @api public
  sig { returns(Pathname) }
  def symlink_location
    return T.must(@symlink_location) if defined?(@symlink_location)

    ext = Pathname(parse_basename(url)).extname
    @symlink_location = T.let(@cache/Utils.safe_filename("#{name}--#{version}#{ext}"), T.nilable(Pathname))
    T.must(@symlink_location)
  end

  # Path for storing the completed download.
  #
  # @api public
  sig { override.returns(Pathname) }
  def cached_location
    return @cached_location if @cached_location

    url_sha256 = Digest::SHA256.hexdigest(url)
    downloads = Pathname.glob(HOMEBREW_CACHE/"downloads/#{url_sha256}--*")
                        .reject { |path| path.extname.end_with?(".incomplete") }

    @cached_location = T.let(
      if downloads.one?
        downloads.fetch(0)
      else
        HOMEBREW_CACHE/"downloads/#{url_sha256}--#{Utils.safe_filename(resolved_basename)}"
      end, T.nilable(Pathname)
    )
    T.must(@cached_location)
  end

  sig { returns(Pathname) }
  def basename
    cached_location.basename.sub(/^[\da-f]{64}--/, "")
  end

  private

  sig { returns(String) }
  def resolved_url
    resolved_url, = resolved_url_and_basename
    resolved_url
  end

  sig { returns(String) }
  def resolved_basename
    _, resolved_basename = resolved_url_and_basename
    resolved_basename
  end

  sig { returns([String, String]) }
  def resolved_url_and_basename
    return T.must(@resolved_url_and_basename) if defined?(@resolved_url_and_basename)

    T.must(@resolved_url_and_basename = T.let([url, parse_basename(url)], T.nilable([String, String])))
  end

  sig { params(url: String, search_query: T::Boolean).returns(String) }
  def parse_basename(url, search_query: true)
    components = { path: T.let([], T::Array[String]), query: T.let([], T::Array[String]) }

    if url.match?(URI::DEFAULT_PARSER.make_regexp)
      uri = URI(url)

      if (uri_query = uri.query.presence)
        URI.decode_www_form(uri_query).each do |key, param|
          components[:query] << param if search_query

          next if key != "response-content-disposition"

          query_basename = param[/attachment;\s*filename=(["']?)(.+)\1/i, 2]
          return File.basename(query_basename) if query_basename
        end
      end

      if (uri_path = uri.path.presence)
        components[:path] = uri_path.split("/").filter_map do |part|
          URI::DEFAULT_PARSER.unescape(part).presence
        end
      end
    else
      components[:path] = [url]
    end

    # We need a Pathname because we've monkeypatched extname to support double
    # extensions (e.g. tar.gz).
    # Given a URL like https://example.com/download.php?file=foo-1.0.tar.gz
    # the basename we want is "foo-1.0.tar.gz", not "download.php".
    [*components[:path], *components[:query]].reverse_each do |path|
      path = Pathname(path)
      return path.basename.to_s if path.extname.present?
    end

    filename = components[:path].last
    return "" if filename.blank?

    File.basename(filename)
  end
end

# Strategy for downloading files using `curl`.
#
# @api public
class CurlDownloadStrategy < AbstractFileDownloadStrategy
  include Utils::Curl

  # url, basename, time, file_size, content_type, is_redirection
  URLMetadata = T.type_alias { [String, String, T.nilable(Time), T.nilable(Integer), T.nilable(String), T::Boolean] }

  sig { returns(T::Array[String]) }
  attr_reader :mirrors

  sig { params(url: String, name: String, version: T.any(NilClass, String, Version), meta: T.untyped).void }
  def initialize(url, name, version, **meta)
    @try_partial = T.let(true, T::Boolean)
    @mirrors = T.let(meta.fetch(:mirrors, []), T::Array[String])

    # Merge `:header` with `:headers`.
    if (header = meta.delete(:header))
      meta[:headers] ||= []
      meta[:headers] << header
    end

    super
  end

  # Download and cache the file at {#cached_location}.
  #
  # @api public
  sig { override.params(timeout: T.any(Float, Integer, NilClass)).void }
  def fetch(timeout: nil)
    end_time = Time.now + timeout if timeout

    download_lock = DownloadLock.new(temporary_path)
    begin
      download_lock.lock

      urls = [url, *mirrors]

      begin
        url = T.must(urls.shift)

        if (domain = Homebrew::EnvConfig.artifact_domain)
          url = url.sub(%r{^https?://#{GitHubPackages::URL_DOMAIN}/}o, "#{domain.chomp("/")}/")
          urls = [] if Homebrew::EnvConfig.artifact_domain_no_fallback?
        end

        ohai "Downloading #{url}"

        cached_location_valid = cached_location.exist?

        resolved_url, _, last_modified, file_size, content_type, is_redirection = begin
          resolve_url_basename_time_file_size(url, timeout: Utils::Timer.remaining!(end_time))
        rescue ErrorDuringExecution
          raise unless cached_location_valid
        end

        # Authorization is no longer valid after redirects
        meta[:headers]&.delete_if { |header| header.start_with?("Authorization") } if is_redirection

        # The cached location is no longer fresh if either:
        # - Last-Modified value is newer than the file's timestamp
        # - Content-Length value is different than the file's size
        if cached_location_valid && (content_type.nil? || !content_type.start_with?("text/"))
          if last_modified && last_modified > cached_location.mtime
            ohai "Ignoring #{cached_location}",
                 "Cached modified time #{cached_location.mtime.iso8601} is before" \
                 "Last-Modified header: #{last_modified.iso8601}"
            cached_location_valid = false
          end
          if file_size&.nonzero? && file_size != cached_location.size
            ohai "Ignoring #{cached_location}",
                 "Cached size #{cached_location.size} differs from " \
                 "Content-Length header: #{file_size}"
            cached_location_valid = false
          end
        end

        if cached_location_valid
          puts "Already downloaded: #{cached_location}"
        else
          begin
            _fetch(url:, resolved_url: T.must(resolved_url), timeout: Utils::Timer.remaining!(end_time))
          rescue ErrorDuringExecution
            raise CurlDownloadStrategyError, url
          end
          cached_location.dirname.mkpath
          temporary_path.rename(cached_location.to_s)
        end

        symlink_location.dirname.mkpath
        FileUtils.ln_s cached_location.relative_path_from(symlink_location.dirname), symlink_location, force: true
      rescue CurlDownloadStrategyError
        raise if urls.empty?

        puts "Trying a mirror..."
        retry
      rescue Timeout::Error => e
        raise Timeout::Error, "Timed out downloading #{self.url}: #{e}"
      end
    ensure
      download_lock.unlock(unlink: true)
    end
  end

  sig { override.void }
  def clear_cache
    super
    rm_rf(temporary_path)
  end

  sig { params(timeout: T.any(Float, Integer, NilClass)).returns([T.nilable(Time), Integer]) }
  def resolved_time_file_size(timeout: nil)
    _, _, time, file_size, = resolve_url_basename_time_file_size(url, timeout:)
    [time, T.must(file_size)]
  end

  private

  sig { params(timeout: T.any(Float, Integer, NilClass)).returns([String, String]) }
  def resolved_url_and_basename(timeout: nil)
    resolved_url, basename, = resolve_url_basename_time_file_size(url, timeout: nil)
    [resolved_url, basename]
  end

  sig { overridable.params(url: String, timeout: T.any(Float, Integer, NilClass)).returns(URLMetadata) }
  def resolve_url_basename_time_file_size(url, timeout: nil)
    @resolved_info_cache ||= T.let({}, T.nilable(T::Hash[String, URLMetadata]))
    return @resolved_info_cache.fetch(url) if @resolved_info_cache.include?(url)

    begin
      parsed_output = curl_headers(url.to_s, wanted_headers: ["content-disposition"], timeout:)
    rescue ErrorDuringExecution
      return [url, parse_basename(url), nil, nil, nil, false]
    end

    parsed_headers = parsed_output.fetch(:responses).map { |r| r.fetch(:headers) }

    final_url = curl_response_follow_redirections(parsed_output.fetch(:responses), url)

    content_disposition_parser = Mechanize::HTTP::ContentDispositionParser.new

    parse_content_disposition = lambda do |line|
      next unless (content_disposition = content_disposition_parser.parse(line.sub(/; *$/, ""), true))

      filename = nil

      if (filename_with_encoding = content_disposition.parameters["filename*"])
        encoding, encoded_filename = filename_with_encoding.split("''", 2)
        # If the `filename*` has incorrectly added double quotes, e.g.
        #   content-disposition: attachment; filename="myapp-1.2.3.pkg"; filename*=UTF-8''"myapp-1.2.3.pkg"
        # Then the encoded_filename will come back as the empty string, in which case we should fall back to the
        # `filename` parameter.
        if encoding.present? && encoded_filename.present?
          filename = URI.decode_www_form_component(encoded_filename).encode(encoding)
        end
      end

      filename = content_disposition.filename if filename.blank?
      next if filename.blank?

      # Servers may include '/' in their Content-Disposition filename header. Take only the basename of this, because:
      # - Unpacking code assumes this is a single file - not something living in a subdirectory.
      # - Directory traversal attacks are possible without limiting this to just the basename.
      File.basename(filename)
    end

    filenames = parsed_headers.flat_map do |headers|
      next [] unless (header = headers["content-disposition"])

      [*parse_content_disposition.call("Content-Disposition: #{header}")]
    end

    time =  parsed_headers
            .flat_map { |headers| [*headers["last-modified"]] }
            .filter_map do |t|
              t.match?(/^\d+$/) ? Time.at(t.to_i) : Time.parse(t)
            rescue ArgumentError # When `Time.parse` gets a badly formatted date.
              nil
            end

    file_size = parsed_headers
                .flat_map { |headers| [*headers["content-length"]&.to_i] }
                .last

    content_type = parsed_headers
                   .flat_map { |headers| [*headers["content-type"]] }
                   .last

    is_redirection = url != final_url
    basename = filenames.last || parse_basename(final_url, search_query: !is_redirection)

    @resolved_info_cache[url] = [final_url, basename, time.last, file_size, content_type, is_redirection]
  end

  sig {
    overridable.params(url: String, resolved_url: String, timeout: T.any(Float, Integer, NilClass))
               .returns(T.nilable(SystemCommand::Result))
  }
  def _fetch(url:, resolved_url:, timeout:)
    ohai "Downloading from #{resolved_url}" if url != resolved_url

    if Homebrew::EnvConfig.no_insecure_redirect? &&
       url.start_with?("https://") && !resolved_url.start_with?("https://")
      $stderr.puts "HTTPS to HTTP redirect detected and HOMEBREW_NO_INSECURE_REDIRECT is set."
      raise CurlDownloadStrategyError, url
    end

    _curl_download resolved_url, temporary_path, timeout
  end

  sig {
    params(resolved_url: String, to: T.any(Pathname, String), timeout: T.any(Float, Integer, NilClass))
      .returns(T.nilable(SystemCommand::Result))
  }
  def _curl_download(resolved_url, to, timeout)
    curl_download resolved_url, to:, try_partial: @try_partial, timeout:
  end

  # Curl options to be always passed to curl,
  # with raw head calls (`curl --head`) or with actual `fetch`.
  sig { returns(T::Array[String]) }
  def _curl_args
    args = []

    args += ["-b", meta.fetch(:cookies).map { |k, v| "#{k}=#{v}" }.join(";")] if meta.key?(:cookies)

    args += ["-e", meta.fetch(:referer)] if meta.key?(:referer)

    args += ["--user", meta.fetch(:user)] if meta.key?(:user)

    args += meta.fetch(:headers, []).flat_map { |h| ["--header", h.strip] }

    args
  end

  sig { returns(T::Hash[Symbol, String]) }
  def _curl_opts
    return { user_agent: meta.fetch(:user_agent) } if meta.key?(:user_agent)

    {}
  end

  sig { override.params(args: String, options: T.untyped).returns(SystemCommand::Result) }
  def curl_output(*args, **options)
    super(*_curl_args, *args, **_curl_opts, **options)
  end

  sig {
    override.params(args: String, print_stdout: T.any(T::Boolean, Symbol), options: T.untyped)
            .returns(SystemCommand::Result)
  }
  def curl(*args, print_stdout: true, **options)
    options[:connect_timeout] = 15 unless mirrors.empty?
    super(*_curl_args, *args, **_curl_opts, **command_output_options, **options)
  end
end

# Strategy for downloading a file using homebrew's curl.
#
# @api public
class HomebrewCurlDownloadStrategy < CurlDownloadStrategy
  private

  sig {
    params(resolved_url: String, to: T.any(Pathname, String), timeout: T.any(Float, Integer, NilClass))
      .returns(T.nilable(SystemCommand::Result))
  }
  def _curl_download(resolved_url, to, timeout)
    raise HomebrewCurlDownloadStrategyError, url unless Formula["curl"].any_version_installed?

    curl_download resolved_url, to:, try_partial: @try_partial, timeout:, use_homebrew_curl: true
  end

  sig { override.params(args: String, options: T.untyped).returns(SystemCommand::Result) }
  def curl_output(*args, **options)
    raise HomebrewCurlDownloadStrategyError, url unless Formula["curl"].any_version_installed?

    options[:use_homebrew_curl] = true
    super
  end
end

# Strategy for downloading a file from an GitHub Packages URL.
#
# @api public
class CurlGitHubPackagesDownloadStrategy < CurlDownloadStrategy
  sig { params(resolved_basename: String).returns(T.nilable(String)) }
  attr_writer :resolved_basename

  sig { params(url: String, name: String, version: T.any(NilClass, String, Version), meta: T.untyped).void }
  def initialize(url, name, version, **meta)
    meta[:headers] ||= []
    # GitHub Packages authorization header.
    # HOMEBREW_GITHUB_PACKAGES_AUTH set in brew.sh
    # If using a private GHCR mirror with no Authentication set then do not add the header. In all other cases add it.
    if !Homebrew::EnvConfig.artifact_domain.presence ||
       Homebrew::EnvConfig.docker_registry_basic_auth_token.presence ||
       Homebrew::EnvConfig.docker_registry_token.presence
      meta[:headers] << "Authorization: #{HOMEBREW_GITHUB_PACKAGES_AUTH}"
    end
    super
  end

  private

  sig { override.params(url: String, timeout: T.any(Float, Integer, NilClass)).returns(URLMetadata) }
  def resolve_url_basename_time_file_size(url, timeout: nil)
    return super if @resolved_basename.blank?

    [url, @resolved_basename, nil, nil, nil, false]
  end
end

# Strategy for downloading a file from an Apache Mirror URL.
#
# @api public
class CurlApacheMirrorDownloadStrategy < CurlDownloadStrategy
  sig { returns(T::Array[String]) }
  def mirrors
    combined_mirrors
  end

  private

  sig { returns(T::Array[String]) }
  def combined_mirrors
    return T.must(@combined_mirrors) if defined?(@combined_mirrors)

    backup_mirrors = unless apache_mirrors["in_attic"]
      apache_mirrors.fetch("backup", [])
                    .map { |mirror| "#{mirror}#{apache_mirrors["path_info"]}" }
    end

    T.must(@combined_mirrors = T.let([*@mirrors, *backup_mirrors], T.nilable(T::Array[String])))
  end

  sig { override.params(url: String, timeout: T.any(Float, Integer, NilClass)).returns(URLMetadata) }
  def resolve_url_basename_time_file_size(url, timeout: nil)
    if url == self.url
      preferred = if apache_mirrors["in_attic"]
        "https://archive.apache.org/dist/"
      else
        apache_mirrors["preferred"]
      end
      super("#{preferred}#{apache_mirrors["path_info"]}", timeout:)
    else
      super
    end
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def apache_mirrors
    return T.must(@apache_mirrors) if defined?(@apache_mirrors)

    json = curl_output("--silent", "--location", "#{url}&asjson=1").stdout
    T.must(@apache_mirrors = T.let(JSON.parse(json), T.nilable(T::Hash[String, T.untyped])))
  rescue JSON::ParserError
    raise CurlDownloadStrategyError, "Couldn't determine mirror, try again later."
  end
end

# Strategy for downloading via an HTTP POST request using `curl`.
# Query parameters on the URL are converted into POST parameters.
#
# @api public
class CurlPostDownloadStrategy < CurlDownloadStrategy
  private

  sig {
    override.params(url: String, resolved_url: String, timeout: T.any(Float, Integer, NilClass))
            .returns(T.nilable(SystemCommand::Result))
  }
  def _fetch(url:, resolved_url:, timeout:)
    args = if meta.key?(:data)
      escape_data = ->(d) { ["-d", URI.encode_www_form([d])] }
      [url, *meta[:data].flat_map(&escape_data)]
    else
      url, query = url.split("?", 2)
      query.nil? ? [url, "-X", "POST"] : [url, "-d", query]
    end

    curl_download(*args, to: temporary_path, try_partial: @try_partial, timeout:)
  end
end

# Strategy for downloading archives without automatically extracting them.
# (Useful for downloading `.jar` files.)
#
# @api public
class NoUnzipCurlDownloadStrategy < CurlDownloadStrategy
  sig { override.params(_block: T.untyped).void }
  def stage(&_block)
    UnpackStrategy::Uncompressed.new(cached_location)
                                .extract(basename:,
                                         verbose:  verbose? && !quiet?)
    yield if block_given?
  end
end

# Strategy for extracting local binary packages.
class LocalBottleDownloadStrategy < AbstractFileDownloadStrategy
  # TODO: Call `super` here
  # rubocop:disable Lint/MissingSuper
  sig { params(path: Pathname).void }
  def initialize(path)
    @cached_location = T.let(path, Pathname)
    extend Pourable
  end
  # rubocop:enable Lint/MissingSuper

  sig { override.void }
  def clear_cache
    # Path is used directly and not cached.
  end
end

# Strategy for downloading a Subversion repository.
#
# @api public
class SubversionDownloadStrategy < VCSDownloadStrategy
  sig { params(url: String, name: String, version: T.any(NilClass, String, Version), meta: T.untyped).void }
  def initialize(url, name, version, **meta)
    super
    @url = @url.sub("svn+http://", "")
  end

  # Download and cache the repository at {#cached_location}.
  #
  # @api public
  sig { override.params(timeout: T.any(Float, Integer, NilClass)).void }
  def fetch(timeout: nil)
    if @url.chomp("/") != repo_url || !silent_command("svn", args: ["switch", @url, cached_location]).success?
      clear_cache
    end
    super
  end

  # Returns the most recent modified time for all files in the current working directory after stage.
  #
  # @api public
  sig { override.returns(Time) }
  def source_modified_time
    require "utils/svn"

    time = if Version.new(T.must(Utils::Svn.version)) >= Version.new("1.9")
      silent_command("svn", args: ["info", "--show-item", "last-changed-date"], chdir: cached_location).stdout
    else
      silent_command("svn", args: ["info"], chdir: cached_location).stdout[/^Last Changed Date: (.+)$/, 1]
    end
    Time.parse T.must(time)
  end

  # Return last commit's unique identifier for the repository.
  #
  # @api public
  sig { override.returns(String) }
  def last_commit
    silent_command("svn", args: ["info", "--show-item", "revision"], chdir: cached_location).stdout.strip
  end

  private

  sig { returns(T.nilable(String)) }
  def repo_url
    silent_command("svn", args: ["info"], chdir: cached_location).stdout.strip[/^URL: (.+)$/, 1]
  end

  sig { params(_block: T.proc.params(arg0: String, arg1: String).void).void }
  def externals(&_block)
    out = silent_command("svn", args: ["propget", "svn:externals", @url]).stdout
    out.chomp.split("\n").each do |line|
      name, url = line.split(/\s+/)
      yield T.must(name), T.must(url)
    end
  end

  sig {
    params(target: Pathname, url: String, revision: T.nilable(String), ignore_externals: T::Boolean,
           timeout: T.nilable(Time)).void
  }
  def fetch_repo(target, url, revision = nil, ignore_externals: false, timeout: nil)
    # Use "svn update" when the repository already exists locally.
    # This saves on bandwidth and will have a similar effect to verifying the
    # cache as it will make any changes to get the right revision.
    args = []
    args << "--quiet" unless verbose?

    if revision
      ohai "Checking out #{@ref}"
      args << "-r" << revision
    end

    args << "--ignore-externals" if ignore_externals

    require "utils/svn"
    args.concat Utils::Svn.invalid_cert_flags if meta[:trust_cert] == true

    if target.directory?
      command! "svn", args: ["update", *args], chdir: target.to_s, timeout: Utils::Timer.remaining(timeout)
    else
      command! "svn", args: ["checkout", url, target, *args], timeout: Utils::Timer.remaining(timeout)
    end
  end

  sig { override.returns(String) }
  def cache_tag
    head? ? "svn-HEAD" : "svn"
  end

  sig { override.returns(T::Boolean) }
  def repo_valid?
    (cached_location/".svn").directory?
  end

  sig { override.params(timeout: T.nilable(Time)).void }
  def clone_repo(timeout: nil)
    case @ref_type
    when :revision
      fetch_repo cached_location, @url, @ref, timeout:
    when :revisions
      # nil is OK for main_revision, as fetch_repo will then get latest
      main_revision = @ref[:trunk]
      fetch_repo(cached_location, @url, main_revision, ignore_externals: true, timeout:)

      externals do |external_name, external_url|
        fetch_repo cached_location/external_name, external_url, @ref[external_name], ignore_externals: true,
                                                                                     timeout:
      end
    else
      fetch_repo cached_location, @url, timeout:
    end
  end
  alias update clone_repo
end

# Strategy for downloading a Git repository.
#
# @api public
class GitDownloadStrategy < VCSDownloadStrategy
  sig { params(url: String, name: String, version: T.any(NilClass, String, Version), meta: T.untyped).void }
  def initialize(url, name, version, **meta)
    # Needs to be before the call to `super`, as the VCSDownloadStrategy's
    # constructor calls `cache_tag` and sets the cache path.
    @only_path = meta[:only_path]

    if @only_path.present?
      # "Cone" mode of sparse checkout requires patterns to be directories
      @only_path = T.let("/#{@only_path}", String) unless @only_path.start_with?("/")
      @only_path = T.let("#{@only_path}/", String) unless @only_path.end_with?("/")
    end

    super
    @ref_type ||= T.let(:branch, T.nilable(Symbol))
    @ref ||= T.let("master", T.untyped)
  end

  # Returns the most recent modified time for all files in the current working directory after stage.
  #
  # @api public
  sig { override.returns(Time) }
  def source_modified_time
    Time.parse(silent_command("git", args: ["--git-dir", git_dir, "show", "-s", "--format=%cD"]).stdout)
  end

  # Return last commit's unique identifier for the repository.
  #
  # @api public
  sig { override.returns(String) }
  def last_commit
    silent_command("git", args: ["--git-dir", git_dir, "rev-parse", "--short=7", "HEAD"]).stdout.chomp
  end

  private

  sig { override.returns(String) }
  def cache_tag
    if partial_clone_sparse_checkout?
      "git-sparse"
    else
      "git"
    end
  end

  sig { returns(Integer) }
  def cache_version
    0
  end

  sig { override.params(timeout: T.nilable(Time)).void }
  def update(timeout: nil)
    config_repo
    update_repo(timeout:)
    checkout(timeout:)
    reset
    update_submodules(timeout:) if submodules?
  end

  sig { returns(T::Boolean) }
  def shallow_dir?
    (git_dir/"shallow").exist?
  end

  sig { returns(Pathname) }
  def git_dir
    cached_location/".git"
  end

  sig { returns(T::Boolean) }
  def ref?
    silent_command("git",
                   args: ["--git-dir", git_dir, "rev-parse", "-q", "--verify", "#{@ref}^{commit}"])
      .success?
  end

  sig { override.returns(String) }
  def current_revision
    silent_command("git", args: ["--git-dir", git_dir, "rev-parse", "-q", "--verify", "HEAD"]).stdout.strip
  end

  sig { override.returns(T::Boolean) }
  def repo_valid?
    silent_command("git", args: ["--git-dir", git_dir, "status", "-s"]).success?
  end

  sig { returns(T::Boolean) }
  def submodules?
    (cached_location/".gitmodules").exist?
  end

  sig { returns(T::Boolean) }
  def partial_clone_sparse_checkout?
    return false if @only_path.blank?

    require "utils/git"
    Utils::Git.supports_partial_clone_sparse_checkout?
  end

  sig { returns(T::Array[String]) }
  def clone_args
    args = %w[clone]

    case @ref_type
    when :branch, :tag
      args << "--branch" << @ref
    end

    args << "--no-checkout" << "--filter=blob:none" if partial_clone_sparse_checkout?

    args << "--config" << "advice.detachedHead=false" # Silences “detached head” warning.
    args << "--config" << "core.fsmonitor=false" # Prevent `fsmonitor` from watching this repository.
    args << @url << cached_location.to_s
  end

  sig { returns(String) }
  def refspec
    case @ref_type
    when :branch then "+refs/heads/#{@ref}:refs/remotes/origin/#{@ref}"
    when :tag    then "+refs/tags/#{@ref}:refs/tags/#{@ref}"
    else              default_refspec
    end
  end

  sig { returns(String) }
  def default_refspec
    # https://git-scm.com/book/en/v2/Git-Internals-The-Refspec
    "+refs/heads/*:refs/remotes/origin/*"
  end

  sig { void }
  def config_repo
    command! "git",
             args:  ["config", "remote.origin.url", @url],
             chdir: cached_location
    command! "git",
             args:  ["config", "remote.origin.fetch", refspec],
             chdir: cached_location
    command! "git",
             args:  ["config", "remote.origin.tagOpt", "--no-tags"],
             chdir: cached_location
    command! "git",
             args:  ["config", "advice.detachedHead", "false"],
             chdir: cached_location
    command! "git",
             args:  ["config", "core.fsmonitor", "false"],
             chdir: cached_location

    return unless partial_clone_sparse_checkout?

    command! "git",
             args:  ["config", "origin.partialclonefilter", "blob:none"],
             chdir: cached_location
    configure_sparse_checkout
  end

  sig { params(timeout: T.nilable(Time)).void }
  def update_repo(timeout: nil)
    return if @ref_type != :branch && ref?

    # Convert any shallow clone to full clone
    if shallow_dir?
      command! "git",
               args:    ["fetch", "origin", "--unshallow"],
               chdir:   cached_location,
               timeout: Utils::Timer.remaining(timeout)
    else
      command! "git",
               args:    ["fetch", "origin"],
               chdir:   cached_location,
               timeout: Utils::Timer.remaining(timeout)
    end
  end

  sig { override.params(timeout: T.nilable(Time)).void }
  def clone_repo(timeout: nil)
    command! "git", args: clone_args, timeout: Utils::Timer.remaining(timeout)

    command! "git",
             args:    ["config", "homebrew.cacheversion", cache_version],
             chdir:   cached_location,
             timeout: Utils::Timer.remaining(timeout)

    configure_sparse_checkout if partial_clone_sparse_checkout?

    checkout(timeout:)
    update_submodules(timeout:) if submodules?
  end

  sig { params(timeout: T.nilable(Time)).void }
  def checkout(timeout: nil)
    ohai "Checking out #{@ref_type} #{@ref}" if @ref
    command! "git", args: ["checkout", "-f", @ref, "--"], chdir: cached_location,
                    timeout: Utils::Timer.remaining(timeout)
  end

  sig { void }
  def reset
    ref = case @ref_type
    when :branch
      "origin/#{@ref}"
    when :revision, :tag
      @ref
    end

    command! "git",
             args:  ["reset", "--hard", *ref, "--"],
             chdir: cached_location
  end

  sig { params(timeout: T.nilable(Time)).void }
  def update_submodules(timeout: nil)
    command! "git",
             args:      ["submodule", "foreach", "--recursive", "git submodule sync"],
             chdir:     cached_location,
             timeout:   Utils::Timer.remaining(timeout),
             reset_uid: true
    command! "git",
             args:      ["submodule", "update", "--init", "--recursive"],
             chdir:     cached_location,
             timeout:   Utils::Timer.remaining(timeout),
             reset_uid: true
    fix_absolute_submodule_gitdir_references!
  end

  # When checking out Git repositories with recursive submodules, some Git
  # versions create `.git` files with absolute instead of relative `gitdir:`
  # pointers. This works for the cached location, but breaks various Git
  # operations once the affected Git resource is staged, i.e. recursively
  # copied to a new location. (This bug was introduced in Git 2.7.0 and fixed
  # in 2.8.3. Clones created with affected version remain broken.)
  # See https://github.com/Homebrew/homebrew-core/pull/1520 for an example.
  sig { void }
  def fix_absolute_submodule_gitdir_references!
    submodule_dirs = command!("git",
                              args:      ["submodule", "--quiet", "foreach", "--recursive", "pwd"],
                              chdir:     cached_location,
                              reset_uid: true).stdout

    submodule_dirs.lines.map(&:chomp).each do |submodule_dir|
      work_dir = Pathname.new(submodule_dir)

      # Only check and fix if `.git` is a regular file, not a directory.
      dot_git = work_dir/".git"
      next unless dot_git.file?

      git_dir = dot_git.read.chomp[/^gitdir: (.*)$/, 1]
      if git_dir.nil?
        onoe "Failed to parse '#{dot_git}'." if Homebrew::EnvConfig.developer?
        next
      end

      # Only attempt to fix absolute paths.
      next unless git_dir.start_with?("/")

      # Make the `gitdir:` reference relative to the working directory.
      relative_git_dir = Pathname.new(git_dir).relative_path_from(work_dir)
      dot_git.atomic_write("gitdir: #{relative_git_dir}\n")
    end
  end

  sig { void }
  def configure_sparse_checkout
    command! "git",
             args:  ["config", "core.sparseCheckout", "true"],
             chdir: cached_location
    command! "git",
             args:  ["config", "core.sparseCheckoutCone", "true"],
             chdir: cached_location

    (git_dir/"info").mkpath
    (git_dir/"info/sparse-checkout").atomic_write("#{@only_path}\n")
  end
end

# Strategy for downloading a Git repository from GitHub.
#
# @api public
class GitHubGitDownloadStrategy < GitDownloadStrategy
  sig { params(url: String, name: String, version: T.nilable(Version), meta: T.untyped).void }
  def initialize(url, name, version, **meta)
    super
    @version = T.let(version, T.nilable(Version))

    match_data = %r{^https?://github\.com/(?<user>[^/]+)/(?<repo>[^/]+)\.git$}.match(@url)
    return unless match_data

    @user = T.let(match_data[:user], T.nilable(String))
    @repo = T.let(match_data[:repo], T.nilable(String))
  end

  sig { override.params(commit: T.nilable(String)).returns(T::Boolean) }
  def commit_outdated?(commit)
    @last_commit ||= GitHub.last_commit(@user, @repo, @ref, version)
    if @last_commit
      return true unless commit
      return true unless @last_commit.start_with?(commit)

      if GitHub.multiple_short_commits_exist?(@user, @repo, commit)
        true
      else
        T.must(@version).update_commit(commit)
        false
      end
    else
      super
    end
  end

  sig { returns(String) }
  def default_refspec
    if default_branch
      "+refs/heads/#{default_branch}:refs/remotes/origin/#{default_branch}"
    else
      super
    end
  end

  sig { returns(T.nilable(String)) }
  def default_branch
    return @default_branch if defined?(@default_branch)

    command! "git",
             args:  ["remote", "set-head", "origin", "--auto"],
             chdir: cached_location

    result = command! "git",
                      args:  ["symbolic-ref", "refs/remotes/origin/HEAD"],
                      chdir: cached_location

    @default_branch = T.let(result.stdout[%r{^refs/remotes/origin/(.*)$}, 1], T.nilable(String))
  end
end

# Strategy for downloading a CVS repository.
#
# @api public
class CVSDownloadStrategy < VCSDownloadStrategy
  sig { params(url: String, name: String, version: T.any(NilClass, String, Version), meta: T.untyped).void }
  def initialize(url, name, version, **meta)
    super
    @url = T.let(@url.sub(%r{^cvs://}, ""), String)

    @module = T.let(
      if meta.key?(:module)
        meta.fetch(:module)
      elsif !@url.match?(%r{:[^/]+$})
        name
      else
        mod, url = split_url(@url)
        @url = T.let(url, String)
        mod
      end, String
    )
  end

  # Returns the most recent modified time for all files in the current working directory after stage.
  #
  # @api public
  sig { override.returns(Time) }
  def source_modified_time
    # Filter CVS's files because the timestamp for each of them is the moment
    # of clone.
    max_mtime = Time.at(0)
    cached_location.find do |f|
      Find.prune if f.directory? && f.basename.to_s == "CVS"
      next unless f.file?

      mtime = f.mtime
      max_mtime = mtime if mtime > max_mtime
    end
    max_mtime
  end

  private

  sig { override.returns(T::Hash[String, String]) }
  def env
    { "PATH" => PATH.new("/usr/bin", Formula["cvs"].opt_bin, ENV.fetch("PATH")) }
  end

  sig { override.returns(String) }
  def cache_tag
    "cvs"
  end

  sig { override.returns(T::Boolean) }
  def repo_valid?
    (cached_location/"CVS").directory?
  end

  sig { returns(T.nilable(String)) }
  def quiet_flag
    "-Q" unless verbose?
  end

  sig { override.params(timeout: T.nilable(Time)).void }
  def clone_repo(timeout: nil)
    # Login is only needed (and allowed) with pserver; skip for anoncvs.
    if @url.include? "pserver"
      command! "cvs", args:    [*quiet_flag, "-d", @url, "login"],
                      timeout: Utils::Timer.remaining(timeout)
    end

    command! "cvs",
             args:    [*quiet_flag, "-d", @url, "checkout", "-d", basename.to_s, @module],
             chdir:   cached_location.dirname,
             timeout: Utils::Timer.remaining(timeout)
  end

  sig { override.params(timeout: T.nilable(Time)).void }
  def update(timeout: nil)
    command! "cvs",
             args:    [*quiet_flag, "update"],
             chdir:   cached_location,
             timeout: Utils::Timer.remaining(timeout)
  end

  sig { params(in_url: String).returns([String, String]) }
  def split_url(in_url)
    parts = in_url.split(":")
    mod = T.must(parts.pop)
    url = parts.join(":")
    [mod, url]
  end
end

# Strategy for downloading a Mercurial repository.
#
# @api public
class MercurialDownloadStrategy < VCSDownloadStrategy
  sig { params(url: String, name: String, version: T.any(NilClass, String, Version), meta: T.untyped).void }
  def initialize(url, name, version, **meta)
    super
    @url = T.let(@url.sub(%r{^hg://}, ""), String)
  end

  # Returns the most recent modified time for all files in the current working directory after stage.
  #
  # @api public
  sig { override.returns(Time) }
  def source_modified_time
    Time.parse(silent_command("hg", args: ["tip", "--template", "{date|isodate}", "-R", cached_location]).stdout)
  end

  # Return last commit's unique identifier for the repository.
  #
  # @api public
  sig { override.returns(String) }
  def last_commit
    silent_command("hg", args: ["parent", "--template", "{node|short}", "-R", cached_location]).stdout.chomp
  end

  private

  sig { override.returns(T::Hash[String, String]) }
  def env
    { "PATH" => PATH.new(Formula["mercurial"].opt_bin, ENV.fetch("PATH")) }
  end

  sig { override.returns(String) }
  def cache_tag
    "hg"
  end

  sig { override.returns(T::Boolean) }
  def repo_valid?
    (cached_location/".hg").directory?
  end

  sig { override.params(timeout: T.nilable(Time)).void }
  def clone_repo(timeout: nil)
    clone_args = %w[clone]

    case @ref_type
    when :branch
      clone_args << "--branch" << @ref
    when :revision, :tag
      clone_args << "--rev" << @ref
    end

    clone_args << @url << cached_location.to_s
    command! "hg", args: clone_args, timeout: Utils::Timer.remaining(timeout)
  end

  sig { override.params(timeout: T.nilable(Time)).void }
  def update(timeout: nil)
    pull_args = %w[pull]

    case @ref_type
    when :branch
      pull_args << "--branch" << @ref
    when :revision, :tag
      pull_args << "--rev" << @ref
    end

    command! "hg", args: ["--cwd", cached_location, *pull_args], timeout: Utils::Timer.remaining(timeout)

    update_args = %w[update --clean]
    update_args << if @ref_type && @ref
      ohai "Checking out #{@ref_type} #{@ref}"
      @ref
    else
      "default"
    end

    command! "hg", args: ["--cwd", cached_location, *update_args], timeout: Utils::Timer.remaining(timeout)
  end

  sig { override.returns(String) }
  def current_revision
    silent_command("hg", args: ["--cwd", cached_location, "identify", "--id"]).stdout.strip
  end
end

# Strategy for downloading a Bazaar repository.
#
# @api public
class BazaarDownloadStrategy < VCSDownloadStrategy
  sig { params(url: String, name: String, version: T.any(NilClass, String, Version), meta: T.untyped).void }
  def initialize(url, name, version, **meta)
    super
    @url = T.let(@url.sub(%r{^bzr://}, ""), String)
  end

  # Returns the most recent modified time for all files in the current working directory after stage.
  #
  # @api public
  sig { override.returns(Time) }
  def source_modified_time
    timestamp = silent_command("bzr", args: ["log", "-l", "1", "--timezone=utc", cached_location]).stdout.chomp
    raise "Could not get any timestamps from bzr!" if timestamp.blank?

    Time.parse(timestamp)
  end

  # Return last commit's unique identifier for the repository.
  #
  # @api public
  sig { override.returns(String) }
  def last_commit
    silent_command("bzr", args: ["revno", cached_location]).stdout.chomp
  end

  private

  sig { override.returns(T::Hash[String, String]) }
  def env
    {
      "PATH"     => PATH.new(Formula["breezy"].opt_bin, ENV.fetch("PATH")),
      "BZR_HOME" => HOMEBREW_TEMP,
    }
  end

  sig { override.returns(String) }
  def cache_tag
    "bzr"
  end

  sig { override.returns(T::Boolean) }
  def repo_valid?
    (cached_location/".bzr").directory?
  end

  sig { override.params(timeout: T.nilable(Time)).void }
  def clone_repo(timeout: nil)
    # "lightweight" means history-less
    command! "bzr",
             args:    ["checkout", "--lightweight", @url, cached_location],
             timeout: Utils::Timer.remaining(timeout)
  end

  sig { override.params(timeout: T.nilable(Time)).void }
  def update(timeout: nil)
    command! "bzr",
             args:    ["update"],
             chdir:   cached_location,
             timeout: Utils::Timer.remaining(timeout)
  end
end

# Strategy for downloading a Fossil repository.
#
# @api public
class FossilDownloadStrategy < VCSDownloadStrategy
  sig { params(url: String, name: String, version: T.any(NilClass, String, Version), meta: T.untyped).void }
  def initialize(url, name, version, **meta)
    super
    @url = T.let(@url.sub(%r{^fossil://}, ""), String)
  end

  # Returns the most recent modified time for all files in the current working directory after stage.
  #
  # @api public
  sig { override.returns(Time) }
  def source_modified_time
    out = silent_command("fossil", args: ["info", "tip", "-R", cached_location]).stdout
    Time.parse(T.must(out[/^(hash|uuid): +\h+ (.+)$/, 1]))
  end

  # Return last commit's unique identifier for the repository.
  #
  # @api public
  sig { override.returns(String) }
  def last_commit
    out = silent_command("fossil", args: ["info", "tip", "-R", cached_location]).stdout
    T.must(out[/^(hash|uuid): +(\h+) .+$/, 1])
  end

  sig { override.returns(T::Boolean) }
  def repo_valid?
    silent_command("fossil", args: ["branch", "-R", cached_location]).success?
  end

  private

  sig { override.returns(T::Hash[String, String]) }
  def env
    { "PATH" => PATH.new(Formula["fossil"].opt_bin, ENV.fetch("PATH")) }
  end

  sig { override.returns(String) }
  def cache_tag
    "fossil"
  end

  sig { override.params(timeout: T.nilable(Time)).void }
  def clone_repo(timeout: nil)
    command! "fossil", args: ["clone", @url, cached_location], timeout: Utils::Timer.remaining(timeout)
  end

  sig { override.params(timeout: T.nilable(Time)).void }
  def update(timeout: nil)
    command! "fossil", args: ["pull", "-R", cached_location], timeout: Utils::Timer.remaining(timeout)
  end
end

# Helper class for detecting a download strategy from a URL.
class DownloadStrategyDetector
  sig {
    params(url: String, using: T.any(NilClass, Symbol, T::Class[AbstractDownloadStrategy]))
      .returns(T::Class[AbstractDownloadStrategy])
  }
  def self.detect(url, using = nil)
    if using.nil?
      detect_from_url(url)
    elsif using.is_a?(Class) && using < AbstractDownloadStrategy
      using
    elsif using.is_a?(Symbol)
      detect_from_symbol(using)
    else
      raise TypeError,
            "Unknown download strategy specification #{using.inspect}"
    end
  end

  sig { params(url: String).returns(T::Class[AbstractDownloadStrategy]) }
  def self.detect_from_url(url)
    case url
    when GitHubPackages::URL_REGEX
      CurlGitHubPackagesDownloadStrategy
    when %r{^https?://github\.com/[^/]+/[^/]+\.git$}
      GitHubGitDownloadStrategy
    when %r{^https?://.+\.git$},
         %r{^git://},
         %r{^https?://git\.sr\.ht/[^/]+/[^/]+$},
         %r{^ssh://git}
      GitDownloadStrategy
    when %r{^https?://www\.apache\.org/dyn/closer\.cgi},
         %r{^https?://www\.apache\.org/dyn/closer\.lua}
      CurlApacheMirrorDownloadStrategy
    when %r{^https?://([A-Za-z0-9\-.]+\.)?googlecode\.com/svn},
         %r{^https?://svn\.},
         %r{^svn://},
         %r{^svn\+http://},
         %r{^http://svn\.apache\.org/repos/},
         %r{^https?://([A-Za-z0-9\-.]+\.)?sourceforge\.net/svnroot/}
      SubversionDownloadStrategy
    when %r{^cvs://}
      CVSDownloadStrategy
    when %r{^hg://},
         %r{^https?://([A-Za-z0-9\-.]+\.)?googlecode\.com/hg},
         %r{^https?://([A-Za-z0-9\-.]+\.)?sourceforge\.net/hgweb/}
      MercurialDownloadStrategy
    when %r{^bzr://}
      BazaarDownloadStrategy
    when %r{^fossil://}
      FossilDownloadStrategy
    else
      CurlDownloadStrategy
    end
  end

  sig { params(symbol: Symbol).returns(T::Class[AbstractDownloadStrategy]) }
  def self.detect_from_symbol(symbol)
    case symbol
    when :hg                     then MercurialDownloadStrategy
    when :nounzip                then NoUnzipCurlDownloadStrategy
    when :git                    then GitDownloadStrategy
    when :bzr                    then BazaarDownloadStrategy
    when :svn                    then SubversionDownloadStrategy
    when :curl                   then CurlDownloadStrategy
    when :homebrew_curl          then HomebrewCurlDownloadStrategy
    when :cvs                    then CVSDownloadStrategy
    when :post                   then CurlPostDownloadStrategy
    when :fossil                 then FossilDownloadStrategy
    else
      raise TypeError, "Unknown download strategy #{symbol} was requested."
    end
  end
end
