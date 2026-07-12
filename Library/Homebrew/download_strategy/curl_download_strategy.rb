# typed: strict
# frozen_string_literal: true

# Strategy for downloading files using `curl`.
#
# @api public
class CurlDownloadStrategy < AbstractFileDownloadStrategy
  include Utils::Curl

  # url, basename, time, file_size, content_type, is_redirection
  URLMetadata = T.type_alias { [String, String, T.nilable(Time), T.nilable(Integer), T.nilable(String), T::Boolean] }

  sig { returns(T::Array[String]) }
  attr_reader :mirrors

  sig { params(url: String, name: String, version: T.nilable(T.any(String, Version)), meta: T.untyped).void }
  def initialize(url, name, version, **meta)
    @try_partial = T.let(true, T::Boolean)
    @expand_deferred_environment = T.let(false, T::Boolean)
    @mirrors = T.let(meta.fetch(:mirrors, []), T::Array[String])
    @file_size = T.let(nil, T.nilable(Integer))
    @last_modified = T.let(nil, T.nilable(Time))

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
  sig { override.params(timeout: T.nilable(T.any(Float, Integer))).void }
  def fetch(timeout: nil)
    end_time = Time.now + timeout if timeout

    download_lock = DownloadLock.new(temporary_path)
    begin
      download_lock.lock

      urls = [url, *mirrors]

      if (domain = Homebrew::EnvConfig.artifact_domain)
        artifact_urls = urls.map do |u|
          u.sub(%r{^https?://#{GitHubPackages::URL_DOMAIN}/}o, "#{domain.chomp("/")}/")
        end

        urls = if Homebrew::EnvConfig.artifact_domain_no_fallback?
          artifact_urls
        else
          # Interleave: try artifact domain first, then original for each URL that was rewritten.
          combined = []
          artifact_urls.zip(urls).each do |artifact_url, original_url|
            combined << artifact_url
            combined << original_url if original_url != artifact_url
          end
          combined
        end
      end

      begin
        url = T.must(urls.shift)

        ohai "Downloading #{url}"

        cached_location_valid = cached_location.exist?

        resolved_url, _, last_modified, @file_size, content_type, is_redirection = begin
          resolve_url_basename_time_file_size(url, timeout: Utils::Timer.remaining!(end_time))
        rescue ErrorDuringExecution
          raise unless cached_location_valid
        end
        @last_modified = last_modified

        # Caller-supplied headers (e.g. tokens) are no longer valid after a
        # redirect to another host, and `Authorization` after any redirect.
        if is_redirection
          if resolved_url && URI(url).host != URI(resolved_url).host
            meta.delete(:headers)
          else
            meta[:headers]&.delete_if { |header| header.start_with?("Authorization") }
          end
        end

        # The cached location is no longer fresh if either:
        # - Last-Modified value is newer than the file's timestamp
        # - Content-Length value is different than the file's size
        if cached_location_valid && (!content_type.is_a?(String) || !content_type.start_with?("text/"))
          if last_modified && last_modified > cached_location.mtime
            ohai "Ignoring #{cached_location}",
                 "Cached modified time #{cached_location.mtime.iso8601} is before " \
                 "Last-Modified header: #{last_modified.iso8601}"
            cached_location_valid = false
          end
          if @file_size&.nonzero? && @file_size != cached_location.size
            ohai "Ignoring #{cached_location}",
                 "Cached size #{cached_location.size} differs from " \
                 "Content-Length header: #{@file_size}"
            cached_location_valid = false
          end
        end

        if cached_location_valid
          puts "Already downloaded: #{cached_location}"
        else
          begin
            _fetch(url:, resolved_url: T.must(resolved_url), timeout: Utils::Timer.remaining!(end_time))
          rescue ErrorDuringExecution => e
            raise CurlDownloadStrategyError.new(url, e.stderr.strip)
          end
          cached_location.dirname.mkpath
          temporary_path.rename(cached_location.to_s)
        end

        create_symlink_to_cached_download(cached_location)
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

  sig { override.returns(T.nilable(Integer)) }
  def total_size
    @file_size
  end

  sig { override.void }
  def clear_cache
    super
    rm_rf(temporary_path)
  end

  sig { params(timeout: T.nilable(T.any(Float, Integer))).returns([T.nilable(Time), Integer]) }
  def resolved_time_file_size(timeout: nil)
    _, _, time, file_size, = resolve_url_basename_time_file_size(url, timeout:)
    [time, T.must(file_size)]
  end

  private

  sig { params(timeout: T.nilable(T.any(Float, Integer))).returns([String, String]) }
  def resolved_url_and_basename(timeout: nil)
    resolved_url, basename, = resolve_url_basename_time_file_size(url, timeout: nil)
    [resolved_url, basename]
  end

  sig { overridable.params(url: String, timeout: T.nilable(T.any(Float, Integer))).returns(URLMetadata) }
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

    # Fallback to content-range header if content-length is not available.
    # Content-Range format: "bytes start-end/total" or "bytes */total" or "bytes start-end/*"
    if file_size.nil? || file_size.zero?
      file_size = parsed_headers
                  .flat_map { |headers| [*headers["content-range"]] }
                  .filter_map { |range| Integer(range.split("/").last, 10, exception: false) }
                  .last
    end

    content_type = parsed_headers
                   .flat_map { |headers| [*headers["content-type"]] }
                   .last

    is_redirection = url != final_url
    basename = filenames.last || parse_basename(final_url, search_query: !is_redirection)

    @resolved_info_cache[url] = [final_url, basename, time.last, file_size, content_type, is_redirection]
  end

  sig {
    overridable.params(url: String, resolved_url: String, timeout: T.nilable(T.any(Float, Integer)))
               .returns(T.nilable(SystemCommand::Result))
  }
  def _fetch(url:, resolved_url:, timeout:)
    ohai "Downloading from #{resolved_url}" if url != resolved_url

    ensure_no_insecure_redirect!(url:, resolved_url:)

    _curl_download resolved_url, temporary_path, timeout
  end

  sig { params(url: String, resolved_url: String).void }
  def ensure_no_insecure_redirect!(url:, resolved_url:)
    return unless insecure_redirect?(url:, resolved_url:)

    error_message = "HTTPS to HTTP redirect detected and `$HOMEBREW_NO_INSECURE_REDIRECT` is set."
    $stderr.puts error_message unless quiet?
    raise CurlDownloadStrategyError.new(url, error_message)
  end

  sig {
    params(resolved_url: String, to: T.any(Pathname, String), timeout: T.nilable(T.any(Float, Integer)))
      .returns(T.nilable(SystemCommand::Result))
  }
  def _curl_download(resolved_url, to, timeout)
    curl_download resolved_url, to:, try_partial: @try_partial, timeout:
  end

  sig { void }
  def allow_deferred_environment_expansion!
    @expand_deferred_environment = true
  end

  sig { params(args: T::Array[String]).returns(T::Array[String]) }
  def expand_deferred_environment_args(args)
    return args unless @expand_deferred_environment

    with_context(deferred_environment_expansion: true) do
      args.map { |arg| ENV.expand_deferred_environment(arg) }
    end
  end

  # Curl options to be always passed to curl,
  # with raw head calls (`curl --head`) or with actual `fetch`.
  sig { returns(T::Array[String]) }
  def _curl_args
    args = []

    args += ["-b", meta.fetch(:cookies).map { |k, v| "#{k}=#{v}" }.join(";")] if meta.key?(:cookies)

    args += ["-e", meta.fetch(:referer)] if meta.key?(:referer)

    args += ["--user", meta.fetch(:user)] if meta.key?(:user)

    if meta.fetch(:headers, []).any? { |header| header.include?(EnvSensitive::DEFERRED_PLACEHOLDER_PREFIX) }
      args += ["--max-redirs", "0"]
    end

    args += expand_deferred_environment_args(meta.fetch(:headers, [])).flat_map { |h| ["--header", h.strip] }

    args
  end

  sig { returns(T::Hash[Symbol, T.any(String, Symbol)]) }
  def _curl_opts
    meta.slice(:user_agent)
  end

  sig { override.params(args: String, options: T.untyped).returns(SystemCommand::Result) }
  def curl_output(*args, **options)
    super(*_curl_args, *expand_deferred_environment_args(args), **_curl_opts, **options)
  end

  sig {
    override.params(args: String, print_stdout: T.any(T::Boolean, Symbol), options: T.untyped)
            .returns(SystemCommand::Result)
  }
  def curl(*args, print_stdout: true, **options)
    options[:connect_timeout] = 15 unless mirrors.empty?
    super(*_curl_args, *expand_deferred_environment_args(args), **_curl_opts, **command_output_options, **options)
  end
end
