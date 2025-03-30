# typed: strict
# frozen_string_literal: true

require "open3"

require "utils/timer"
require "system_command"

module Utils
  # Helper function for interacting with `curl`.
  module Curl
    include SystemCommand::Mixin
    extend SystemCommand::Mixin
    extend T::Helpers

    requires_ancestor { Kernel }

    # Error returned when the server sent data curl could not parse.
    CURL_WEIRD_SERVER_REPLY_EXIT_CODE = 8

    # Error returned when `--fail` is used and the HTTP server returns an error
    # code that is >= 400.
    CURL_HTTP_RETURNED_ERROR_EXIT_CODE = 22

    # Error returned when curl gets an error from the lowest networking layers
    # that the receiving of data failed.
    CURL_RECV_ERROR_EXIT_CODE = 56

    # This regex is used to extract the part of an ETag within quotation marks,
    # ignoring any leading weak validator indicator (`W/`). This simplifies
    # ETag comparison in `#curl_check_http_content`.
    ETAG_VALUE_REGEX = %r{^(?:[wW]/)?"((?:[^"]|\\")*)"}

    # HTTP responses and body content are typically separated by a double
    # `CRLF` (whereas HTTP header lines are separated by a single `CRLF`).
    # In rare cases, this can also be a double newline (`\n\n`).
    HTTP_RESPONSE_BODY_SEPARATOR = "\r\n\r\n"

    # This regex is used to isolate the parts of an HTTP status line, namely
    # the status code and any following descriptive text (e.g. `Not Found`).
    HTTP_STATUS_LINE_REGEX = %r{^HTTP/.* (?<code>\d+)(?: (?<text>[^\r\n]+))?}

    private_constant :CURL_WEIRD_SERVER_REPLY_EXIT_CODE,
                     :CURL_HTTP_RETURNED_ERROR_EXIT_CODE,
                     :CURL_RECV_ERROR_EXIT_CODE,
                     :ETAG_VALUE_REGEX, :HTTP_RESPONSE_BODY_SEPARATOR,
                     :HTTP_STATUS_LINE_REGEX

    module_function

    sig { params(use_homebrew_curl: T::Boolean).returns(T.any(Pathname, String)) }
    def curl_executable(use_homebrew_curl: false)
      return HOMEBREW_BREWED_CURL_PATH if use_homebrew_curl

      @curl_executable ||= T.let(HOMEBREW_SHIMS_PATH/"shared/curl", T.nilable(T.any(Pathname, String)))
    end

    sig { returns(String) }
    def curl_path
      @curl_path ||= T.let(
        Utils.popen_read(curl_executable, "--homebrew=print-path").chomp.presence,
        T.nilable(String),
      )
    end

    sig { void }
    def clear_path_cache
      @curl_path = nil
    end

    sig {
      params(
        extra_args:      String,
        connect_timeout: T.any(Integer, Float, NilClass),
        max_time:        T.any(Integer, Float, NilClass),
        retries:         T.nilable(Integer),
        retry_max_time:  T.any(Integer, Float, NilClass),
        show_output:     T.nilable(T::Boolean),
        show_error:      T.nilable(T::Boolean),
        user_agent:      T.any(String, Symbol, NilClass),
        referer:         T.nilable(String),
      ).returns(T::Array[String])
    }
    def curl_args(
      *extra_args,
      connect_timeout: nil,
      max_time: nil,
      retries: Homebrew::EnvConfig.curl_retries.to_i,
      retry_max_time: nil,
      show_output: false,
      show_error: true,
      user_agent: nil,
      referer: nil
    )
      args = []

      # do not load .curlrc unless requested (must be the first argument)
      curlrc = Homebrew::EnvConfig.curlrc
      if curlrc&.start_with?("/")
        # If the file exists, we still want to disable loading the default curlrc.
        args << "--disable" << "--config" << curlrc
      elsif curlrc
        # This matches legacy behavior: `HOMEBREW_CURLRC` was a bool,
        # omitting `--disable` when present.
      else
        args << "--disable"
      end

      # echo any cookies received on a redirect
      args << "--cookie" << File::NULL

      args << "--globoff"

      args << "--show-error" if show_error

      args << "--user-agent" << case user_agent
      when :browser, :fake
        HOMEBREW_USER_AGENT_FAKE_SAFARI
      when :default, nil
        HOMEBREW_USER_AGENT_CURL
      when String
        user_agent
      else
        raise TypeError, ":user_agent must be :browser/:fake, :default, or a String"
      end

      args << "--header" << "Accept-Language: en"

      if show_output != true
        args << "--fail"
        args << "--progress-bar" unless Context.current.verbose?
        args << "--verbose" if Homebrew::EnvConfig.curl_verbose?
        args << "--silent" if !$stdout.tty? || Context.current.quiet?
      end

      args << "--connect-timeout" << connect_timeout.round(3) if connect_timeout.present?
      args << "--max-time" << max_time.round(3) if max_time.present?

      # A non-positive integer (e.g. 0) or `nil` will omit this argument
      args << "--retry" << retries if retries&.positive?

      args << "--retry-max-time" << retry_max_time.round if retry_max_time.present?

      args << "--referer" << referer if referer.present?

      (args + extra_args).map(&:to_s)
    end

    sig {
      params(
        args:              String,
        secrets:           T.any(String, T::Array[String]),
        print_stdout:      T.any(T::Boolean, Symbol),
        print_stderr:      T.any(T::Boolean, Symbol),
        debug:             T.nilable(T::Boolean),
        verbose:           T.nilable(T::Boolean),
        env:               T::Hash[String, String],
        timeout:           T.nilable(T.any(Integer, Float)),
        use_homebrew_curl: T::Boolean,
        options:           T.untyped,
      ).returns(SystemCommand::Result)
    }
    def curl_with_workarounds(
      *args,
      secrets: [], print_stdout: false, print_stderr: false, debug: nil,
      verbose: nil, env: {}, timeout: nil, use_homebrew_curl: false, **options
    )
      end_time = Time.now + timeout if timeout

      command_options = {
        secrets:,
        print_stdout:,
        print_stderr:,
        debug:,
        verbose:,
      }.compact

      result = system_command curl_executable(use_homebrew_curl:),
                              args:    curl_args(*args, **options),
                              env:,
                              timeout: Utils::Timer.remaining(end_time),
                              **command_options

      return result if result.success? || args.include?("--http1.1")

      raise Timeout::Error, result.stderr.lines.last.chomp if timeout && result.status.exitstatus == 28

      # Error in the HTTP2 framing layer
      if result.exit_status == 16
        return curl_with_workarounds(
          *args, "--http1.1",
          timeout: Utils::Timer.remaining(end_time), **command_options, **options
        )
      end

      # This is a workaround for https://github.com/curl/curl/issues/1618.
      if result.exit_status == 56 # Unexpected EOF
        out = curl_output("-V").stdout

        # If `curl` doesn't support HTTP2, the exception is unrelated to this bug.
        return result unless out.include?("HTTP2")

        # The bug is fixed in `curl` >= 7.60.0.
        curl_version = out[/curl (\d+(\.\d+)+)/, 1]
        return result if Gem::Version.new(curl_version) >= Gem::Version.new("7.60.0")

        return curl_with_workarounds(*args, "--http1.1", **command_options, **options)
      end

      result
    end

    sig {
      overridable.params(
        args:         String,
        print_stdout: T.any(T::Boolean, Symbol),
        options:      T.untyped,
      ).returns(SystemCommand::Result)
    }
    def curl(*args, print_stdout: true, **options)
      result = curl_with_workarounds(*args, print_stdout:, **options)
      result.assert_success!
      result
    end

    sig {
      params(
        args:        String,
        to:          T.any(Pathname, String),
        try_partial: T::Boolean,
        options:     T.untyped,
      ).returns(T.nilable(SystemCommand::Result))
    }
    def curl_download(*args, to:, try_partial: false, **options)
      destination = Pathname(to)
      destination.dirname.mkpath

      args = ["--location", *args]

      if try_partial && destination.exist?
        headers = begin
          parsed_output = curl_headers(*args, **options, wanted_headers: ["accept-ranges"])
          parsed_output.fetch(:responses).last&.fetch(:headers) || {}
        rescue ErrorDuringExecution
          # Ignore errors here and let actual download fail instead.
          {}
        end

        # Any value for `Accept-Ranges` other than `none` indicates that the server
        # supports partial requests. Its absence indicates no support.
        supports_partial = headers.fetch("accept-ranges", "none") != "none"
        content_length = headers["content-length"]&.to_i

        if supports_partial
          # We've already downloaded all bytes.
          return if destination.size == content_length

          args = ["--continue-at", "-", *args]
        end
      end

      args = ["--remote-time", "--output", destination.to_s, *args]

      curl(*args, **options)
    end

    sig { overridable.params(args: String, options: T.untyped).returns(SystemCommand::Result) }
    def curl_output(*args, **options)
      curl_with_workarounds(*args, print_stderr: false, show_output: true, **options)
    end

    sig {
      params(
        args:           String,
        wanted_headers: T::Array[String],
        options:        T.untyped,
      ).returns(T::Hash[Symbol, T.untyped])
    }
    def curl_headers(*args, wanted_headers: [], **options)
      base_args = ["--fail", "--location", "--silent"]
      get_retry_args = []
      if (is_post_request = args.include?("POST"))
        base_args << "--dump-header" << "-"
      else
        base_args << "--head"
        get_retry_args << "--request" << "GET"
      end

      # This is a workaround for https://github.com/Homebrew/brew/issues/18213
      get_retry_args << "--http1.1" if curl_version >= Version.new("8.7") && curl_version < Version.new("8.10")

      [[], get_retry_args].each do |request_args|
        result = curl_output(*base_args, *request_args, *args, **options)

        # We still receive usable headers with certain non-successful exit
        # statuses, so we special case them below.
        if result.success? || [
          CURL_WEIRD_SERVER_REPLY_EXIT_CODE,
          CURL_HTTP_RETURNED_ERROR_EXIT_CODE,
          CURL_RECV_ERROR_EXIT_CODE,
        ].include?(result.exit_status)
          parsed_output = parse_curl_output(result.stdout)
          return parsed_output if is_post_request

          if request_args.empty?
            # If we didn't get any wanted header yet, retry using `GET`.
            next if wanted_headers.any? &&
                    parsed_output.fetch(:responses).none? { |r| r.fetch(:headers).keys.intersect?(wanted_headers) }

            # Some CDNs respond with 400 codes for `HEAD` but resolve with `GET`.
            next if (400..499).cover?(parsed_output.fetch(:responses).last&.fetch(:status_code).to_i)
          end

          return parsed_output if result.success? ||
                                  result.exit_status == CURL_WEIRD_SERVER_REPLY_EXIT_CODE
        end

        result.assert_success!
      end

      {}
    end

    # Check if a URL is protected by CloudFlare (e.g. badlion.net and jaxx.io).
    # @param response [Hash] A response hash from `#parse_curl_response`.
    # @return [true, false] Whether a response contains headers indicating that
    #   the URL is protected by Cloudflare.
    sig { params(response: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
    def url_protected_by_cloudflare?(response)
      return false if response[:headers].blank?
      return false unless [403, 503].include?(response[:status_code].to_i)

      [*response[:headers]["server"]].any? { |server| server.match?(/^cloudflare/i) }
    end

    # Check if a URL is protected by Incapsula (e.g. corsair.com).
    # @param response [Hash] A response hash from `#parse_curl_response`.
    # @return [true, false] Whether a response contains headers indicating that
    #   the URL is protected by Incapsula.
    sig { params(response: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
    def url_protected_by_incapsula?(response)
      return false if response[:headers].blank?
      return false if response[:status_code].to_i != 403

      set_cookie_header = Array(response[:headers]["set-cookie"])
      set_cookie_header.compact.any? { |cookie| cookie.match?(/^(visid_incap|incap_ses)_/i) }
    end

    sig {
      params(
        url:               String,
        url_type:          String,
        specs:             T::Hash[Symbol, String],
        user_agents:       T::Array[T.any(String, Symbol)],
        referer:           T.nilable(String),
        check_content:     T::Boolean,
        strict:            T::Boolean,
        use_homebrew_curl: T::Boolean,
      ).returns(T.nilable(String))
    }
    def curl_check_http_content(url, url_type, specs: {}, user_agents: [:default], referer: nil,
                                check_content: false, strict: false, use_homebrew_curl: false)
      return unless url.start_with? "http"

      secure_url = url.sub(/\Ahttp:/, "https:")
      secure_details = T.let(nil, T.nilable(T::Hash[Symbol, T.untyped]))
      hash_needed = T.let(false, T::Boolean)
      if url != secure_url
        user_agents.each do |user_agent|
          secure_details = begin
            curl_http_content_headers_and_checksum(
              secure_url,
              specs:,
              hash_needed:       true,
              use_homebrew_curl:,
              user_agent:,
              referer:,
            )
          rescue Timeout::Error
            next
          end

          next unless http_status_ok?(secure_details[:status_code])

          hash_needed = true
          user_agents = [user_agent]
          break
        end
      end

      details = T.let({}, T::Hash[Symbol, T.untyped])
      attempts = 0
      user_agents.each do |user_agent|
        loop do
          details = curl_http_content_headers_and_checksum(
            url,
            specs:,
            hash_needed:,
            use_homebrew_curl:,
            user_agent:,
            referer:,
          )

          # Retry on network issues
          break if details[:exit_status] != 52 && details[:exit_status] != 56

          attempts += 1
          break if attempts >= Homebrew::EnvConfig.curl_retries.to_i
        end

        break if http_status_ok?(details[:status_code])
      end

      return "The #{url_type} #{url} is not reachable" unless details[:status_code]

      unless http_status_ok?(details[:status_code])
        return if details[:responses].any? do |response|
          url_protected_by_cloudflare?(response) || url_protected_by_incapsula?(response)
        end

        # https://github.com/Homebrew/brew/issues/13789
        # If the `:homepage` of a formula is private, it will fail an `audit`
        # since there's no way to specify a `strategy` with `using:` and
        # GitHub does not authorize access to the web UI using token
        #
        # Strategy:
        # If the `:homepage` 404s, it's a GitHub link and we have a token then
        # check the API (which does use tokens) for the repository
        repo_details = url.match(%r{https?://github\.com/(?<user>[^/]+)/(?<repo>[^/]+)/?.*})
        check_github_api = url_type == SharedAudits::URL_TYPE_HOMEPAGE &&
                           details[:status_code] == "404" &&
                           repo_details &&
                           Homebrew::EnvConfig.github_api_token.present?

        unless check_github_api
          return "The #{url_type} #{url} is not reachable (HTTP status code #{details[:status_code]})"
        end

        if SharedAudits.github_repo_data(T.must(repo_details[:user]), T.must(repo_details[:repo])).nil?
          "Unable to find homepage"
        end
      end

      if url.start_with?("https://") && Homebrew::EnvConfig.no_insecure_redirect? &&
         details[:final_url].present? && !details[:final_url].start_with?("https://")
        return "The #{url_type} #{url} redirects back to HTTP"
      end

      return unless secure_details

      return if !http_status_ok?(details[:status_code]) || !http_status_ok?(secure_details[:status_code])

      etag_match = details[:etag] &&
                   details[:etag] == secure_details[:etag]
      content_length_match =
        details[:content_length] &&
        details[:content_length] == secure_details[:content_length]
      file_match = details[:file_hash] == secure_details[:file_hash]

      http_with_https_available =
        url.start_with?("http://") &&
        secure_details[:final_url].present? && secure_details[:final_url].start_with?("https://")

      if (etag_match || content_length_match || file_match) && http_with_https_available
        return "The #{url_type} #{url} should use HTTPS rather than HTTP"
      end

      return unless check_content

      no_protocol_file_contents = %r{https?:\\?/\\?/}
      http_content = details[:file]&.scrub&.gsub(no_protocol_file_contents, "/")
      https_content = secure_details[:file]&.scrub&.gsub(no_protocol_file_contents, "/")

      # Check for the same content after removing all protocols
      if http_content && https_content && (http_content == https_content) && http_with_https_available
        return "The #{url_type} #{url} should use HTTPS rather than HTTP"
      end

      return unless strict

      # Same size, different content after normalization
      # (typical causes: Generated ID, Timestamp, Unix time)
      if http_content.length == https_content.length
        return "The #{url_type} #{url} may be able to use HTTPS rather than HTTP. Please verify it in a browser."
      end

      lenratio = (https_content.length * 100 / http_content.length).to_i
      return unless (90..110).cover?(lenratio)

      "The #{url_type} #{url} may be able to use HTTPS rather than HTTP. Please verify it in a browser."
    end

    sig {
      params(
        url:               String,
        specs:             T::Hash[Symbol, String],
        hash_needed:       T::Boolean,
        use_homebrew_curl: T::Boolean,
        user_agent:        T.any(String, Symbol),
        referer:           T.nilable(String),
      ).returns(T::Hash[Symbol, T.untyped])
    }
    def curl_http_content_headers_and_checksum(
      url, specs: {}, hash_needed: false,
      use_homebrew_curl: false, user_agent: :default, referer: nil
    )
      file = Tempfile.new.tap(&:close)

      # Convert specs to options. This is mostly key-value options,
      # unless the value is a boolean in which case treat as as flag.
      specs = specs.flat_map do |option, argument|
        next [] if argument == false # No flag.

        args = ["--#{option.to_s.tr("_", "-")}"]
        args << argument if argument != true # It's a flag.
        args
      end

      max_time = hash_needed ? 600 : 25
      output, _, status = curl_output(
        *specs, "--dump-header", "-", "--output", file.path, "--location", url,
        use_homebrew_curl:,
        connect_timeout:   15,
        max_time:,
        retry_max_time:    max_time,
        user_agent:,
        referer:
      )

      parsed_output = parse_curl_output(output)
      responses = parsed_output[:responses]

      final_url = curl_response_last_location(responses)
      headers = if responses.last.present?
        status_code = responses.last[:status_code]
        responses.last[:headers]
      else
        {}
      end
      etag = headers["etag"][ETAG_VALUE_REGEX, 1] if headers["etag"].present?
      content_length = headers["content-length"]

      if status.success?
        open_args = {}
        content_type = headers["content-type"]

        # Use the last `Content-Type` header if there is more than one instance
        # in the response
        content_type = content_type.last if content_type.is_a?(Array)

        # Try to get encoding from Content-Type header
        # TODO: add guessing encoding by <meta http-equiv="Content-Type" ...> tag
        if content_type &&
           (match = content_type.match(/;\s*charset\s*=\s*([^\s]+)/)) &&
           (charset = match[1])
          begin
            open_args[:encoding] = Encoding.find(charset)
          rescue ArgumentError
            # Unknown charset in Content-Type header
          end
        end
        file_contents = File.read(T.must(file.path), **open_args)
        file_hash = Digest::SHA256.hexdigest(file_contents) if hash_needed
      end

      {
        url:,
        final_url:,
        exit_status:    status.exitstatus,
        status_code:,
        headers:,
        etag:,
        content_length:,
        file:           file_contents,
        file_hash:,
        responses:,
      }
    ensure
      T.must(file).unlink
    end

    sig { returns(Version) }
    def curl_version
      @curl_version ||= T.let({}, T.nilable(T::Hash[String, Version]))
      @curl_version[curl_path] ||= Version.new(T.must(curl_output("-V").stdout[/curl (\d+(\.\d+)+)/, 1]))
    end

    sig { returns(T::Boolean) }
    def curl_supports_fail_with_body?
      @curl_supports_fail_with_body ||= T.let(Hash.new do |h, key|
        h[key] = curl_version >= Version.new("7.76.0")
      end, T.nilable(T::Hash[T.any(Pathname, String), T::Boolean]))
      @curl_supports_fail_with_body[curl_path]
    end

    sig { returns(T::Boolean) }
    def curl_supports_tls13?
      @curl_supports_tls13 ||= T.let(Hash.new do |h, key|
        h[key] = quiet_system(curl_executable, "--tlsv1.3", "--head", "https://brew.sh/")
      end, T.nilable(T::Hash[T.any(Pathname, String), T::Boolean]))
      @curl_supports_tls13[curl_path]
    end

    sig { params(status: T.nilable(String)).returns(T::Boolean) }
    def http_status_ok?(status)
      return false if status.nil?

      (100..299).cover?(status.to_i)
    end

    # Separates the output text from `curl` into an array of HTTP responses and
    # the final response body (i.e. content). Response hashes contain the
    # `:status_code`, `:status_text` and `:headers`.
    # @param output [String] The output text from `curl` containing HTTP
    #   responses, body content, or both.
    # @param max_iterations [Integer] The maximum number of iterations for the
    #   `while` loop that parses HTTP response text. This should correspond to
    #   the maximum number of requests in the output. If `curl`'s `--max-redirs`
    #   option is used, `max_iterations` should be `max-redirs + 1`, to
    #   account for any final response after the redirections.
    # @return [Hash] A hash containing an array of response hashes and the body
    #   content, if found.
    sig { params(output: String, max_iterations: Integer).returns(T::Hash[Symbol, T.untyped]) }
    def parse_curl_output(output, max_iterations: 25)
      responses = []

      iterations = 0
      output = output.lstrip
      while output.match?(%r{\AHTTP/[\d.]+ \d+}) && output.include?(HTTP_RESPONSE_BODY_SEPARATOR)
        iterations += 1
        raise "Too many redirects (max = #{max_iterations})" if iterations > max_iterations

        response_text, _, output = output.partition(HTTP_RESPONSE_BODY_SEPARATOR)
        output = output.lstrip
        next if response_text.blank?

        response_text.chomp!
        response = parse_curl_response(response_text)
        responses << response if response.present?
      end

      { responses:, body: output }
    end

    # Returns the URL from the last location header found in cURL responses,
    # if any.
    # @param responses [Array<Hash>] An array of hashes containing response
    #   status information and headers from `#parse_curl_response`.
    # @param absolutize [true, false] Whether to make the location URL absolute.
    # @param base_url [String, nil] The URL to use as a base for making the
    #   `location` URL absolute.
    # @return [String, nil] The URL from the last-occurring `location` header
    #   in the responses or `nil` (if no `location` headers found).
    sig {
      params(
        responses:  T::Array[T::Hash[Symbol, T.untyped]],
        absolutize: T::Boolean,
        base_url:   T.nilable(String),
      ).returns(T.nilable(String))
    }
    def curl_response_last_location(responses, absolutize: false, base_url: nil)
      responses.reverse_each do |response|
        next if response[:headers].blank?

        location = response[:headers]["location"]
        next if location.blank?

        absolute_url = URI.join(base_url, location).to_s if absolutize && base_url.present?
        return absolute_url || location
      end

      nil
    end

    # Returns the final URL by following location headers in cURL responses.
    # @param responses [Array<Hash>] An array of hashes containing response
    #   status information and headers from `#parse_curl_response`.
    # @param base_url [String] The URL to use as a base.
    # @return [String] The final absolute URL after redirections.
    sig {
      params(
        responses: T::Array[T::Hash[Symbol, T.untyped]],
        base_url:  String,
      ).returns(String)
    }
    def curl_response_follow_redirections(responses, base_url)
      responses.each do |response|
        next if response[:headers].blank?

        location = response[:headers]["location"]
        next if location.blank?

        base_url = URI.join(base_url, location).to_s
      end

      base_url
    end

    private

    # Parses HTTP response text from `curl` output into a hash containing the
    # information from the status line (status code and, optionally,
    # descriptive text) and headers.
    # @param response_text [String] The text of a `curl` response, consisting
    #   of a status line followed by header lines.
    # @return [Hash] A hash containing the response status information and
    #   headers (as a hash with header names as keys).
    sig { params(response_text: String).returns(T::Hash[Symbol, T.untyped]) }
    def parse_curl_response(response_text)
      response = {}
      return response unless (match = response_text.match(HTTP_STATUS_LINE_REGEX))

      # Parse the status line and remove it
      response[:status_code] = match["code"]
      response[:status_text] = match["text"] if match["text"].present?
      response_text = response_text.sub(%r{^HTTP/.* (\d+).*$\s*}, "")

      # Create a hash from the header lines
      response[:headers] = {}
      response_text.split("\r\n").each do |line|
        header_name, header_value = line.split(/:\s*/, 2)
        next if header_name.blank? || header_value.nil?

        header_name = header_name.strip.downcase
        header_value.strip!

        case response[:headers][header_name]
        when String
          response[:headers][header_name] = [response[:headers][header_name], header_value]
        when Array
          response[:headers][header_name].push(header_value)
        else
          response[:headers][header_name] = header_value
        end

        response[:headers][header_name]
      end

      response
    end
  end
end
