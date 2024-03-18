# typed: true
# frozen_string_literal: true

require "open3"

require "utils/timer"
require "system_command"

module Utils
  # Helper function for interacting with `curl`.
  #
  # @api private
  module Curl
    include SystemCommand::Mixin
    extend SystemCommand::Mixin

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

    private_constant :ETAG_VALUE_REGEX, :HTTP_RESPONSE_BODY_SEPARATOR, :HTTP_STATUS_LINE_REGEX

    module_function

    def curl_executable(use_homebrew_curl: false)
      return HOMEBREW_BREWED_CURL_PATH if use_homebrew_curl

      @curl_executable ||= HOMEBREW_SHIMS_PATH/"shared/curl"
    end

    def curl_path
      @curl_path ||= Utils.popen_read(curl_executable, "--homebrew=print-path").chomp.presence
    end

    def clear_path_cache
      @curl_path = nil
    end

    sig {
      params(
        extra_args:      T.untyped,
        connect_timeout: T.any(Integer, Float, NilClass),
        max_time:        T.any(Integer, Float, NilClass),
        retries:         T.nilable(Integer),
        retry_max_time:  T.any(Integer, Float, NilClass),
        show_output:     T.nilable(T::Boolean),
        show_error:      T.nilable(T::Boolean),
        user_agent:      T.any(String, Symbol, NilClass),
        referer:         T.nilable(String),
      ).returns(T::Array[T.untyped])
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
      args << "--cookie" << "/dev/null"

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

      args + extra_args
    end

    def curl_with_workarounds(
      *args,
      secrets: nil, print_stdout: nil, print_stderr: nil, debug: nil,
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

    def curl(*args, print_stdout: true, **options)
      result = curl_with_workarounds(*args, print_stdout:, **options)
      result.assert_success!
      result
    end

    def curl_download(*args, to: nil, try_partial: false, **options)
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

      args = ["--remote-time", "--output", destination, *args]

      curl(*args, **options)
    end

    def curl_output(*args, **options)
      curl_with_workarounds(*args, print_stderr: false, show_output: true, **options)
    end

    def curl_headers(*args, wanted_headers: [], **options)
      [[], ["--request", "GET"]].each do |request_args|
        result = curl_output(
          "--fail", "--location", "--silent", "--head", *request_args, *args,
          **options
        )

        # 22 means a non-successful HTTP status code, not a `curl` error, so we still got some headers.
        if result.success? || result.exit_status == 22
          parsed_output = parse_curl_output(result.stdout)

          if request_args.empty?
            # If we didn't get any wanted header yet, retry using `GET`.
            next if wanted_headers.any? &&
                    parsed_output.fetch(:responses).none? { |r| (r.fetch(:headers).keys & wanted_headers).any? }

            # Some CDNs respond with 400 codes for `HEAD` but resolve with `GET`.
            next if (400..499).cover?(parsed_output.fetch(:responses).last&.fetch(:status_code).to_i)
          end

          return parsed_output if result.success?
        end

        result.assert_success!
      end
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

      details = T.let(nil, T.nilable(T::Hash[Symbol, T.untyped]))
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
        # If the `:homepage` 404s, it's a GitHub link, and we have a token then
        # check the API (which does use tokens) for the repository
        repo_details = url.match(%r{https?://github\.com/(?<user>[^/]+)/(?<repo>[^/]+)/?.*})
        check_github_api = url_type == SharedAudits::URL_TYPE_HOMEPAGE &&
                           details[:status_code] == "404" &&
                           repo_details &&
                           Homebrew::EnvConfig.github_api_token

        unless check_github_api
          return "The #{url_type} #{url} is not reachable (HTTP status code #{details[:status_code]})"
        end

        "Unable to find homepage" if SharedAudits.github_repo_data(repo_details[:user], repo_details[:repo]).nil?
      end

      if url.start_with?("https://") && Homebrew::EnvConfig.no_insecure_redirect? &&
         (details[:final_url].present? && !details[:final_url].start_with?("https://"))
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
        (secure_details[:final_url].present? && secure_details[:final_url].start_with?("https://"))

      if (etag_match || content_length_match || file_match) && http_with_https_available
        return "The #{url_type} #{url} should use HTTPS rather than HTTP"
      end

      return unless check_content

      no_protocol_file_contents = %r{https?:\\?/\\?/}
      http_content = details[:file]&.scrub&.gsub(no_protocol_file_contents, "/")
      https_content = secure_details[:file]&.scrub&.gsub(no_protocol_file_contents, "/")

      # Check for the same content after removing all protocols
      if (http_content && https_content) && (http_content == https_content) && http_with_https_available
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
        # Try to get encoding from Content-Type header
        # TODO: add guessing encoding by <meta http-equiv="Content-Type" ...> tag
        if (content_type = headers["content-type"]) &&
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

    def curl_supports_tls13?
      @curl_supports_tls13 ||= Hash.new do |h, key|
        h[key] = quiet_system(curl_executable, "--tlsv1.3", "--head", "https://brew.sh/")
      end
      @curl_supports_tls13[curl_path]
    end

    def http_status_ok?(status)
      (100..299).cover?(status.to_i)
    end

    # Separates the output text from `curl` into an array of HTTP responses and
    # the final response body (i.e. content). Response hashes contain the
    # `:status_code`, `:status_text`, and `:headers`.
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
      return response unless response_text.match?(HTTP_STATUS_LINE_REGEX)

      # Parse the status line and remove it
      match = T.must(response_text.match(HTTP_STATUS_LINE_REGEX))
      response[:status_code] = match["code"] if match["code"].present?
      response[:status_text] = match["text"] if match["text"].present?
      response_text = response_text.sub(%r{^HTTP/.* (\d+).*$\s*}, "")

      # Create a hash from the header lines
      response[:headers] = {}
      response_text.split("\r\n").each do |line|
        header_name, header_value = line.split(/:\s*/, 2)
        next if header_name.blank?

        header_name = header_name.strip.downcase
        header_value&.strip!

        case response[:headers][header_name]
        when nil
          response[:headers][header_name] = header_value
        when String
          response[:headers][header_name] = [response[:headers][header_name], header_value]
        when Array
          response[:headers][header_name].push(header_value)
        end

        response[:headers][header_name]
      end

      response
    end
  end
end
