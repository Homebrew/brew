# typed: strict
# frozen_string_literal: true

require "utils/output"

require "open3"

require "utils/timer"
require "utils/curl/responses"
require "system_command"

module Utils
  # Helper function for interacting with `curl`.
  module Curl
    include SystemCommand::Mixin
    extend SystemCommand::Mixin
    include Utils::Output::Mixin
    extend Utils::Output::Mixin
    extend T::Helpers

    requires_ancestor { Kernel }

    # Error returned when the server sent data curl could not parse.
    CURL_WEIRD_SERVER_REPLY_EXIT_CODE = 8

    # Error returned when `--fail` is used and the HTTP server returns an error
    # code that is >= 400.
    CURL_HTTP_RETURNED_ERROR_EXIT_CODE = 22

    # Error returned when an operation took longer than the given timeout.
    CURL_OPERATION_TIMEOUT_EXIT_CODE = 28

    # Error returned when the server closed the connection without replying.
    CURL_GOT_NOTHING_EXIT_CODE = 52

    # Error returned when curl gets an error from the lowest networking layers
    # that the receiving of data failed.
    CURL_RECV_ERROR_EXIT_CODE = 56

    # Failures that can occur after the request has been sent.
    CURL_REQUEST_SENT_EXIT_CODES = T.let([
      CURL_OPERATION_TIMEOUT_EXIT_CODE,
      CURL_GOT_NOTHING_EXIT_CODE,
      CURL_RECV_ERROR_EXIT_CODE,
    ].freeze, T::Array[Integer])

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

    HTTPS_REDIRECT_CURL_ARGS = ["--proto-redir", "=https"].freeze

    # A `--progress-bar` percentage (e.g. "50.0%"); may belong to an earlier,
    # unrelated request, so it's stripped rather than kept.
    PROGRESS_BAR_REGEX = /\A#*\s*\d{1,3}\.\d%\s*/

    private_constant :CURL_WEIRD_SERVER_REPLY_EXIT_CODE,
                     :CURL_HTTP_RETURNED_ERROR_EXIT_CODE,
                     :CURL_RECV_ERROR_EXIT_CODE,
                     :CURL_OPERATION_TIMEOUT_EXIT_CODE,
                     :CURL_GOT_NOTHING_EXIT_CODE,
                     :CURL_REQUEST_SENT_EXIT_CODES,
                     :ETAG_VALUE_REGEX, :HTTP_RESPONSE_BODY_SEPARATOR,
                     :HTTP_STATUS_LINE_REGEX,
                     :HTTPS_REDIRECT_CURL_ARGS, :PROGRESS_BAR_REGEX

    include Responses
    extend Responses

    private :http_status_ok?, :parse_curl_output, :curl_response_last_location,
            :curl_response_follow_redirections, :parse_curl_response,
            :url_protected_by_cloudflare?, :url_protected_by_incapsula?

    module_function

    sig { params(use_homebrew_curl: T::Boolean).returns(T.any(Pathname, String)) }
    def curl_executable(use_homebrew_curl: false)
      return HOMEBREW_BREWED_CURL_PATH if use_homebrew_curl

      @curl_executable ||= T.let(HOMEBREW_SHIMS_PATH/"shared/curl", T.nilable(T.any(Pathname, String)))
    end

    sig { returns(String) }
    def curl_path
      @curl_path ||= T.let(
        Utils.popen_read(curl_executable, "--homebrew=print-path").chomp,
        T.nilable(String),
      )
      odie("Failed to get curl path") if @curl_path.blank?
      @curl_path
    end

    sig { void }
    def clear_path_cache
      ENV.delete("HOMEBREW_CURL_VERSION")
      ENV.delete("HOMEBREW_CURL_VERSION_PATH")
      @curl_path = nil
      @curl_version = nil
      @curl_supports_fail_with_body = nil
      @curl_supports_tls13 = nil
    end

    # Keep environment options in sync with setup_curl_args in utils/curl.sh.
    sig {
      params(
        extra_args:      String,
        connect_timeout: T.nilable(T.any(Integer, Float)),
        max_time:        T.nilable(T.any(Integer, Float)),
        retries:         T.nilable(Integer),
        retry_max_time:  T.nilable(T.any(Integer, Float)),
        show_output:     T.nilable(T::Boolean),
        show_error:      T.nilable(T::Boolean),
        cookies:         T.nilable(T::Hash[String, String]),
        header:          T.nilable(T.any(String, T::Array[String])),
        referer:         T.nilable(String),
        user_agent:      T.nilable(T.any(String, Symbol)),
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
      cookies: nil,
      header: nil,
      referer: nil,
      user_agent: nil
    )
      args = []

      # Personal curl defaults can change downloads or the output Homebrew parses.
      # --disable must be first to ignore them, even when the shim adds certificate options.
      curlrc = Homebrew::EnvConfig.curlrc
      if curlrc&.start_with?("/")
        # Load only the explicit config; --config alone also loads the default curlrc.
        args << "--disable" << "--config" << curlrc
      elsif curlrc
        # This matches legacy behaviour: `HOMEBREW_CURLRC` was a bool,
        # omitting `--disable` when present.
      else
        args << "--disable"
      end

      args << "--cookie" << if cookies
        cookies.map { |k, v| "#{k}=#{v}" }.join(";")
      else
        # Echo any cookies received on a redirect
        File::NULL
      end

      args << "--globoff"

      args << "--show-error" if show_error

      if user_agent != :curl
        args << "--user-agent" << case user_agent
        when :browser, :fake
          HOMEBREW_USER_AGENT_FAKE_SAFARI
        when :default, nil
          HOMEBREW_USER_AGENT_CURL
        when String
          user_agent
        else
          raise TypeError, ":user_agent must be :browser/:fake, :default, :curl, or a String"
        end
      end

      args << "--header" << "Accept-Language: en"
      case header
      when String
        args << "--header" << header
      when Array
        header.each { |h| args << "--header" << h.strip }
      end

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

    sig { params(url: String, resolved_url: String).returns(T::Boolean) }
    def insecure_redirect?(url:, resolved_url:)
      Homebrew::EnvConfig.no_insecure_redirect? &&
        url.start_with?("https://") && !resolved_url.start_with?("https://")
    end

    sig { returns(T::Array[String]) }
    def https_redirect_curl_args
      HTTPS_REDIRECT_CURL_ARGS
    end

    # Keep redirect policy in sync with setup_curl_args in utils/curl.sh.
    sig { params(args: T::Array[String]).returns(T::Array[String]) }
    def no_insecure_redirect_curl_args(args)
      return args unless Homebrew::EnvConfig.no_insecure_redirect?

      # `--proto-redir =https` tells `curl --location` to reject any redirect
      # target that is not HTTPS. Drop caller-provided values first so they
      # cannot relax the HTTPS-only redirect policy.
      args = args.each_with_index.filter_map do |arg, i|
        next if arg == "--proto-redir"
        next if i.positive? && args.fetch(i - 1) == "--proto-redir"
        next if arg.start_with?("--proto-redir=")

        arg
      end
      return args unless args.include?("--location")

      # This blocks an HTTPS request from following a redirect to HTTP at the
      # curl layer, including cases where a preflight request saw a different
      # redirect chain than the real download.
      [*https_redirect_curl_args, *args]
    end

    sig {
      params(
        args:              String,
        secrets:           T.any(String, T::Array[String]),
        print_stdout:      T.any(T::Boolean, Symbol),
        print_stderr:      T.any(T::Boolean, Symbol),
        debug:             T.nilable(T::Boolean),
        verbose:           T.nilable(T::Boolean),
        timeout:           T.nilable(T.any(Integer, Float)),
        use_homebrew_curl: T::Boolean,
        connect_timeout:   T.nilable(T.any(Integer, Float)),
        max_time:          T.nilable(T.any(Integer, Float)),
        retries:           T.nilable(Integer),
        retry_max_time:    T.nilable(T.any(Integer, Float)),
        show_output:       T.nilable(T::Boolean),
        show_error:        T.nilable(T::Boolean),
        cookies:           T.nilable(T::Hash[String, String]),
        header:            T.nilable(T.any(String, T::Array[String])),
        referer:           T.nilable(String),
        user_agent:        T.nilable(T.any(String, Symbol)),
      ).returns(SystemCommand::Result)
    }
    def curl_with_workarounds(
      *args,
      secrets: [], print_stdout: false, print_stderr: false, debug: nil, verbose: nil, timeout: nil,
      use_homebrew_curl: false, connect_timeout: nil, max_time: nil, retries: Homebrew::EnvConfig.curl_retries.to_i,
      retry_max_time: nil, show_output: false, show_error: true, cookies: nil, header: nil, referer: nil,
      user_agent: nil
    )
      args = no_insecure_redirect_curl_args(args)
      end_time = Time.now + timeout if timeout

      input = +""
      # Keep header input in sync with setup_curl_header in utils/curl.sh.
      command_args = curl_args(
        *args,
        connect_timeout:, max_time:, retries:, retry_max_time:, show_output:, show_error:, cookies:, header:,
        referer:, user_agent:
      ).each_with_object([]) do |arg, filtered_args|
        if filtered_args.last == "--header" && arg.match?(/\AAuthorization:/i)
          # odeprecated "Remove this version check and the older-curl branches when the minimum curl is 7.55."
          header_input_supported =
            curl_version(use_homebrew_curl:) >= Version.new(HOMEBREW_CURL_HEADER_FILE_MIN_VERSION)
          if header_input_supported || arg.match?(/\AAuthorization:\s*token /i)
            filtered_args.pop
            input << "#{arg}\n" if header_input_supported
            next
          end
        end
        filtered_args << arg
      end
      command_args += ["--header", "@-"] unless input.empty?

      result = system_command curl_executable(use_homebrew_curl:),
                              args:         command_args,
                              input:,
                              print_stdout:,
                              print_stderr:,
                              debug:,
                              verbose:,
                              secrets:,
                              timeout:      Utils::Timer.remaining(end_time)

      return result if result.success? || args.include?("--http1.1")

      raise Timeout::Error, result.stderr.lines.fetch(-1).chomp if timeout && result.status.exitstatus == 28

      # Error in the HTTP2 framing layer
      if result.exit_status == 16
        return curl_with_workarounds(
          *args, "--http1.1",
          secrets:, print_stdout:, print_stderr:, debug:, verbose:, timeout: Utils::Timer.remaining(end_time),
          use_homebrew_curl:, connect_timeout:, max_time:, retries:, retry_max_time:, show_output:, show_error:,
          cookies:, header:, referer:, user_agent:
        )
      end

      # This is a workaround for https://github.com/curl/curl/issues/1618.
      if result.exit_status == 56 # Unexpected EOF
        out = curl_output("-V", use_homebrew_curl:).stdout

        # If `curl` doesn't support HTTP2, the exception is unrelated to this bug.
        return result unless out.include?("HTTP2")

        # The bug is fixed in `curl` >= 7.60.0.
        curl_version = out[/curl (\d+(?:\.\d+)+)/, 1]
        return result if Gem::Version.new(curl_version) >= Gem::Version.new("7.60.0")

        return curl_with_workarounds(
          *args, "--http1.1",
          secrets:, print_stdout:, print_stderr:, debug:, verbose:, timeout: Utils::Timer.remaining!(end_time),
          use_homebrew_curl:, connect_timeout:, max_time:, retries:, retry_max_time:, show_output:, show_error:,
          cookies:, header:, referer:, user_agent:
        )
      end

      result
    end

    sig {
      overridable.params(
        args:              String,
        secrets:           T.any(String, T::Array[String]),
        print_stdout:      T.any(T::Boolean, Symbol),
        print_stderr:      T.any(T::Boolean, Symbol),
        debug:             T.nilable(T::Boolean),
        verbose:           T.nilable(T::Boolean),
        timeout:           T.nilable(T.any(Integer, Float)),
        use_homebrew_curl: T::Boolean,
        connect_timeout:   T.nilable(T.any(Integer, Float)),
        max_time:          T.nilable(T.any(Integer, Float)),
        retries:           T.nilable(Integer),
        retry_max_time:    T.nilable(T.any(Integer, Float)),
        show_error:        T.nilable(T::Boolean),
        cookies:           T.nilable(T::Hash[String, String]),
        header:            T.nilable(T.any(String, T::Array[String])),
        referer:           T.nilable(String),
        user_agent:        T.nilable(T.any(String, Symbol)),
      ).returns(SystemCommand::Result)
    }
    def curl(
      *args, secrets: [], print_stdout: true, print_stderr: false, debug: nil, verbose: nil, timeout: nil,
      use_homebrew_curl: false, connect_timeout: nil, max_time: nil, retries: Homebrew::EnvConfig.curl_retries.to_i,
      retry_max_time: nil, show_error: true, cookies: nil, header: nil, referer: nil, user_agent: nil
    )
      result = curl_with_workarounds(
        *args, secrets:, print_stdout:, print_stderr:, debug:, verbose:, timeout:, use_homebrew_curl:,
        connect_timeout:, max_time:, retries:, retry_max_time:, show_error:, cookies:, header:, referer:, user_agent:
      )
      result.assert_success!
      result
    end

    # `timeout` covers the resume probe and the download together.
    sig {
      params(
        args:              String,
        to:                T.any(Pathname, String),
        try_partial:       T::Boolean,
        timeout:           T.nilable(T.any(Integer, Float)),
        secrets:           T.any(String, T::Array[String]),
        print_stdout:      T.any(T::Boolean, Symbol),
        use_homebrew_curl: T::Boolean,
        retries:           T.nilable(Integer),
        show_error:        T.nilable(T::Boolean),
        header:            T.nilable(T.any(String, T::Array[String])),
      ).returns(T.nilable(SystemCommand::Result))
    }
    def curl_download(
      *args, to:, try_partial: false, timeout: nil, secrets: [], print_stdout: true, use_homebrew_curl: false,
      retries: Homebrew::EnvConfig.curl_retries.to_i, show_error: true, header: nil
    )
      end_time = Time.now + timeout if timeout
      destination = Pathname(to)
      destination.dirname.mkpath

      args = ["--location", *args]

      if try_partial && destination.exist?
        headers = begin
          parsed_output = curl_headers(
            *args, secrets:, use_homebrew_curl:, retries:, show_error:, header:,
            wanted_headers: ["accept-ranges"], deadline: end_time
          )
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

      curl(
        *args, secrets:, print_stdout:, timeout: Utils::Timer.remaining!(end_time), use_homebrew_curl:,
        retries:, show_error:, header:
      )
    rescue ErrorDuringExecution => e
      raise if e.exitstatus != 23 # CURLE_WRITE_ERROR

      raise DownloadWriteError, <<~EOS
        Could not write download to #{destination}
        Check that the destination has enough free disk space and is writable.
        #{strip_progress_bar(Tty.collapse_carriage_returns(e.stderr)).strip}
      EOS
    end

    # Run after `Tty.collapse_carriage_returns`; a bar-only line becomes empty.
    sig { params(string: String).returns(String) }
    def strip_progress_bar(string)
      string.split("\n", -1).map { |line| line.sub(PROGRESS_BAR_REGEX, "") }.join("\n")
    end

    sig {
      overridable.params(
        args:              String,
        secrets:           T.any(String, T::Array[String]),
        print_stdout:      T.any(T::Boolean, Symbol),
        print_stderr:      T.any(T::Boolean, Symbol),
        debug:             T.nilable(T::Boolean),
        verbose:           T.nilable(T::Boolean),
        timeout:           T.nilable(T.any(Integer, Float)),
        use_homebrew_curl: T::Boolean,
        connect_timeout:   T.nilable(T.any(Integer, Float)),
        max_time:          T.nilable(T.any(Integer, Float)),
        retries:           T.nilable(Integer),
        retry_max_time:    T.nilable(T.any(Integer, Float)),
        show_error:        T.nilable(T::Boolean),
        cookies:           T.nilable(T::Hash[String, String]),
        header:            T.nilable(T.any(String, T::Array[String])),
        referer:           T.nilable(String),
        user_agent:        T.nilable(T.any(String, Symbol)),
      ).returns(SystemCommand::Result)
    }
    def curl_output(
      *args,
      secrets: [], print_stdout: false, print_stderr: false, debug: nil, verbose: nil, timeout: nil,
      use_homebrew_curl: false, connect_timeout: nil, max_time: nil, retries: Homebrew::EnvConfig.curl_retries.to_i,
      retry_max_time: nil, show_error: true, cookies: nil, header: nil, referer: nil, user_agent: nil
    )
      curl_with_workarounds(
        *args,
        secrets:, print_stdout:, print_stderr:, debug:, verbose:, timeout:, use_homebrew_curl:, connect_timeout:,
        max_time:, retries:, retry_max_time:, show_output: true, show_error:, cookies:, header:, referer:,
        user_agent:
      )
    end

    # `timeout` applies to each curl process; `deadline` bounds all requests.
    sig {
      params(
        args:              String,
        wanted_headers:    T::Array[String],
        timeout:           T.nilable(T.any(Integer, Float)),
        deadline:          T.nilable(Time),
        secrets:           T.any(String, T::Array[String]),
        print_stdout:      T.any(T::Boolean, Symbol),
        print_stderr:      T.any(T::Boolean, Symbol),
        debug:             T.nilable(T::Boolean),
        verbose:           T.nilable(T::Boolean),
        use_homebrew_curl: T::Boolean,
        connect_timeout:   T.nilable(T.any(Integer, Float)),
        max_time:          T.nilable(T.any(Integer, Float)),
        retries:           T.nilable(Integer),
        retry_max_time:    T.nilable(T.any(Integer, Float)),
        show_error:        T.nilable(T::Boolean),
        cookies:           T.nilable(T::Hash[String, String]),
        header:            T.nilable(T.any(String, T::Array[String])),
        referer:           T.nilable(String),
        user_agent:        T.nilable(T.any(String, Symbol)),
      ).returns(T::Hash[Symbol, T.untyped])
    }
    def curl_headers(
      *args, wanted_headers: [], timeout: nil, deadline: nil, secrets: [], print_stdout: false, print_stderr: false,
      debug: nil, verbose: nil, use_homebrew_curl: false, connect_timeout: nil, max_time: nil,
      retries: Homebrew::EnvConfig.curl_retries.to_i, retry_max_time: nil, show_error: true, cookies: nil,
      header: nil, referer: nil, user_agent: nil
    )
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
        result = curl_output(
          *base_args, *request_args, *args, secrets:, print_stdout:, print_stderr:, debug:, verbose:,
          timeout: [timeout, Utils::Timer.remaining!(deadline)].compact.min, use_homebrew_curl:, connect_timeout:,
          max_time:, retries:, retry_max_time:, show_error:, cookies:, header:, referer:, user_agent:
        )

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
      # The body is only read to compare an HTTP URL with its HTTPS counterpart.
      head_only = T.let(url == secure_url, T::Boolean)
      user_agents.each do |user_agent|
        loop do
          details = curl_http_content_headers_and_checksum(
            url,
            specs:,
            hash_needed:,
            head_only:,
            use_homebrew_curl:,
            user_agent:,
            referer:,
          )

          # Some servers reject `HEAD` but serve `GET`.
          # DNS and connection failures happen before the request is sent.
          head_rejected = if (status_code = details[:status_code])
            !http_status_ok?(status_code)
          else
            CURL_REQUEST_SENT_EXIT_CODES.include?(details[:exit_status])
          end

          if head_only && head_rejected
            head_only = false
            next
          end

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

        # TODO: `utils/shared_audits` requires this file in turn.
        require "utils/shared_audits"

        # https://github.com/Homebrew/brew/issues/13789
        # If the `:homepage` of a formula is private, it will fail an `audit`
        # since there's no way to specify a `strategy` with `using:` and
        # GitHub does not authorize access to the web UI using token
        #
        # Strategy:
        # If the `:homepage` 404s, it's a GitHub link and we have a token then
        # check the API (which does use tokens) for the repository
        github_repo_regex = %r{https?://github\.com/(?<user>[^/]+)/(?<repo>[^/]+)/?.*}
        user = url[github_repo_regex, :user]
        repo = url[github_repo_regex, :repo]
        if url_type != SharedAudits::URL_TYPE_HOMEPAGE || details[:status_code] != "404" ||
           user.nil? || repo.nil? || Homebrew::EnvConfig.github_api_token.blank?
          return "The #{url_type} #{url} is not reachable (HTTP status code #{details[:status_code]})"
        end

        if SharedAudits.github_repo_data(user, repo).nil?
          "Unable to find homepage"
        end
      end

      if details[:final_url].present? && insecure_redirect?(url:, resolved_url: details[:final_url])
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
      http_content, https_content = [details, secure_details].map do |response|
        content = response[:file]&.scrub&.gsub(no_protocol_file_contents, "/")
        # Each side may declare a different charset, so compare both as UTF-8.
        content&.encode("UTF-8", invalid: :replace, undef: :replace)
      rescue Encoding::ConverterNotFoundError
        # e.g. Windows-1258 has no converter, so compare it as it is.
        content
      end

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
        head_only:         T::Boolean,
        use_homebrew_curl: T::Boolean,
        user_agent:        T.any(String, Symbol),
        referer:           T.nilable(String),
      ).returns(T::Hash[Symbol, T.untyped])
    }
    def curl_http_content_headers_and_checksum(
      url, specs: {}, hash_needed: false, head_only: false,
      use_homebrew_curl: false, user_agent: :default, referer: nil
    )
      file = Tempfile.new.tap(&:close)

      # Convert specs to options. This is mostly key-value options,
      # unless the value is a boolean in which case treat as a flag.
      specs = specs.flat_map do |option, argument|
        next [] if argument == false # No flag.

        args = ["--#{option.to_s.tr("_", "-")}"]
        args << argument if argument != true # It's a flag.
        args
      end

      max_time = hash_needed ? 600 : 25
      # `--head` prints the headers itself, so `--dump-header` would duplicate them.
      output_args = if head_only
        ["--head"]
      else
        ["--dump-header", "-", "--output", file.path]
      end
      output, _, status = curl_output(
        *specs, *output_args, "--location", url,
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
      etag_header = Array(headers["etag"]).last
      etag = etag_header[ETAG_VALUE_REGEX, 1] if etag_header.present?
      content_length = headers["content-length"]

      if !head_only && status.success? && (file_path = file.path)
        file_hash = Digest::SHA256.file(file_path).hexdigest if hash_needed

        # Only load file contents for text-based content comparison on small files.
        # Large binary files don't benefit from content comparison.
        max_read_size = 100 * 1024 * 1024
        if File.size(file_path) <= max_read_size
          open_args = {}
          content_type = Array(headers["content-type"]).last

          # Try to get encoding from Content-Type header, then from a `<meta>` tag
          # outside comments in the first 1024 bytes as browsers do.
          charset = content_type[/;\s*charset\s*=\s*"?([^\s";]+)/i, 1] if content_type
          charset ||= File.binread(file_path, 1024).to_s
                          .gsub(/<!--.*?(?:-->|\z)/m, "")[/<meta[^>]*[\s;]charset\s*=\s*["']?([\w-]+)/i, 1]
          begin
            if charset
              encoding = Encoding.find(charset)
              # Content is compared with ASCII regexes, which raise on e.g. UTF-16.
              open_args[:encoding] = encoding if encoding.ascii_compatible?
            end
          rescue ArgumentError
            # Unknown charset
          end

          file_contents = File.read(file_path, **open_args)
        end
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
      file&.unlink
    end

    sig { params(use_homebrew_curl: T::Boolean).returns(Version) }
    def curl_version(use_homebrew_curl: false)
      if use_homebrew_curl
        require "keg"

        return Keg.for(HOMEBREW_BREWED_CURL_PATH).version.version
      end

      # setup_curl in utils/curl.sh passes the version for its selected executable.
      if (version = ENV.fetch("HOMEBREW_CURL_VERSION", nil))&.match?(/\A\d+\.\d+(?:\.\d+)?\z/) &&
         curl_path == ENV["HOMEBREW_CURL_VERSION_PATH"] && curl_path == ENV["HOMEBREW_CURL"]
        return Version.new(version)
      end

      @curl_version ||= T.let({}, T.nilable(T::Hash[String, Version]))
      @curl_version[curl_path] ||= begin
        # Version probes must not include a download strategy's headers.
        result = curl_with_workarounds("-V", print_stderr: false, show_output: true)
        version = result.stdout[/curl (\d+(?:\.\d+)+)/, 1]
        if !result.success? || version.nil?
          require "utils/tool"
          Utils::Tool.invalidate_cache(:curl)
          result.assert_success!
          odie("Failed to parse curl version from #{result.stdout}")
        end
        Version.new(version)
      end
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
        h[key] = SystemCommand.quiet_system(curl_executable, *curl_args("--tlsv1.3", "--head", "https://brew.sh/"))
      end, T.nilable(T::Hash[T.any(Pathname, String), T::Boolean]))
      @curl_supports_tls13[curl_path]
    end
  end
end
