# typed: false
# frozen_string_literal: true

require "open3"

require "extend/time"

module Utils
  # Helper function for interacting with `curl`.
  #
  # @api private
  module Curl
    using TimeRemaining

    module_function

    def curl_executable
      @curl ||= [
        ENV["HOMEBREW_CURL"],
        which("curl"),
        "/usr/bin/curl",
      ].compact.map { |c| Pathname(c) }.find(&:executable?)
      raise "No executable `curl` was found" unless @curl

      @curl
    end

    def curl_args(*extra_args, **options)
      args = []

      # do not load .curlrc unless requested (must be the first argument)
      args << "--disable" unless Homebrew::EnvConfig.curlrc?

      args << "--globoff"

      args << "--show-error"

      args << "--user-agent" << case options[:user_agent]
      when :browser, :fake
        HOMEBREW_USER_AGENT_FAKE_SAFARI
      when :default, nil
        HOMEBREW_USER_AGENT_CURL
      when String
        options[:user_agent]
      end

      args << "--header" << "Accept-Language: en"

      unless options[:show_output] == true
        args << "--fail"
        args << "--progress-bar" unless Context.current.verbose?
        args << "--verbose" if Homebrew::EnvConfig.curl_verbose?
        args << "--silent" unless $stdout.tty?
      end

      args << "--connect-timeout" << connect_timeout.round(3) if options[:connect_timeout]
      args << "--max-time" << max_time.round(3) if options[:max_time]
      args << "--retry" << Homebrew::EnvConfig.curl_retries unless options[:retry] == false
      args << "--retry-max-time" << retry_max_time.round if options[:retry_max_time]

      args + extra_args
    end

    def curl_with_workarounds(
      *args,
      secrets: nil, print_stdout: nil, print_stderr: nil, debug: nil, verbose: nil, env: {}, timeout: nil, **options
    )
      end_time = Time.now + timeout if timeout

      command_options = {
        secrets:      secrets,
        print_stdout: print_stdout,
        print_stderr: print_stderr,
        debug:        debug,
        verbose:      verbose,
      }.compact

      # SSL_CERT_FILE can be incorrectly set by users or portable-ruby and screw
      # with SSL downloads so unset it here.
      result = system_command curl_executable,
                              args:    curl_args(*args, **options),
                              env:     { "SSL_CERT_FILE" => nil }.merge(env),
                              timeout: end_time&.remaining,
                              **command_options

      return result if result.success? || !args.exclude?("--http1.1")

      raise Timeout::Error, result.stderr.lines.last.chomp if timeout && result.status.exitstatus == 28

      # Error in the HTTP2 framing layer
      if result.status.exitstatus == 16
        return curl_with_workarounds(
          *args, "--http1.1",
          timeout: end_time&.remaining, **command_options, **options
        )
      end

      # This is a workaround for https://github.com/curl/curl/issues/1618.
      if result.status.exitstatus == 56 # Unexpected EOF
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
      result = curl_with_workarounds(*args, print_stdout: print_stdout, **options)
      result.assert_success!
      result
    end

    def parse_headers(headers)
      return {} if headers.blank?

      # Skip status code
      headers.split("\r\n")[1..].to_h do |h|
        name, content = h.split(": ")
        [name.downcase, content]
      end
    end

    def curl_download(*args, to: nil, try_partial: true, **options)
      destination = Pathname(to)
      destination.dirname.mkpath

      if try_partial
        range_stdout = curl_output("--location", "--head", *args, **options).stdout
        headers = parse_headers(range_stdout.split("\r\n\r\n").first)

        # Any value for `accept-ranges` other than none indicates that the server supports partial requests.
        # Its absence indicates no support.
        supports_partial = headers.key?("accept-ranges") && headers["accept-ranges"] != "none"

        if supports_partial &&
           destination.exist? &&
           destination.size == headers["content-length"].to_i
          return # We've already downloaded all the bytes
        end
      end

      args = ["--location", "--remote-time", "--output", destination, *args]
      # continue-at shouldn't be used with servers that don't support partial requests.
      args = ["--continue-at", "-", *args] if destination.exist? && supports_partial

      curl(*args, **options)
    end

    def curl_output(*args, **options)
      curl_with_workarounds(*args, print_stderr: false, show_output: true, **options)
    end

    # Check if a URL is protected by CloudFlare (e.g. badlion.net and jaxx.io).
    def url_protected_by_cloudflare?(details)
      return false unless details[:headers]

      [403, 503].include?(details[:status].to_i) &&
        details[:headers].match?(/^Set-Cookie: __cfduid=/i) &&
        details[:headers].match?(/^Server: cloudflare/i)
    end

    # Check if a URL is protected by Incapsula (e.g. corsair.com).
    def url_protected_by_incapsula?(details)
      return false unless details[:headers]

      details[:status].to_i == 403 &&
        details[:headers].match?(/^Set-Cookie: visid_incap_/i) &&
        details[:headers].match?(/^Set-Cookie: incap_ses_/i)
    end

    def curl_check_http_content(url, url_type, specs: {}, user_agents: [:default],
                                check_content: false, strict: false)
      return unless url.start_with? "http"

      secure_url = url.sub(/\Ahttp:/, "https:")
      secure_details = nil
      hash_needed = false
      if url != secure_url
        user_agents.each do |user_agent|
          secure_details = begin
            curl_http_content_headers_and_checksum(secure_url, specs: specs, hash_needed: true,
                                                   user_agent: user_agent)
          rescue Timeout::Error
            next
          end

          next unless http_status_ok?(secure_details[:status])

          hash_needed = true
          user_agents = [user_agent]
          break
        end
      end

      details = nil
      user_agents.each do |user_agent|
        details =
          curl_http_content_headers_and_checksum(url, specs: specs, hash_needed: hash_needed, user_agent: user_agent)
        break if http_status_ok?(details[:status])
      end

      unless details[:status]
        # Hack around https://github.com/Homebrew/brew/issues/3199
        return if MacOS.version == :el_capitan

        return "The #{url_type} #{url} is not reachable"
      end

      unless http_status_ok?(details[:status])
        return if url_protected_by_cloudflare?(details) || url_protected_by_incapsula?(details)

        return "The #{url_type} #{url} is not reachable (HTTP status code #{details[:status]})"
      end

      if url.start_with?("https://") && Homebrew::EnvConfig.no_insecure_redirect? &&
         !details[:final_url]&.start_with?("https://")
        return "The #{url_type} #{url} redirects back to HTTP"
      end

      return unless secure_details

      return if !http_status_ok?(details[:status]) || !http_status_ok?(secure_details[:status])

      etag_match = details[:etag] &&
                   details[:etag] == secure_details[:etag]
      content_length_match =
        details[:content_length] &&
        details[:content_length] == secure_details[:content_length]
      file_match = details[:file_hash] == secure_details[:file_hash]

      if (etag_match || content_length_match || file_match) &&
         secure_details[:final_url]&.start_with?("https://") &&
         url.start_with?("http://")
        return "The #{url_type} #{url} should use HTTPS rather than HTTP"
      end

      return unless check_content

      no_protocol_file_contents = %r{https?:\\?/\\?/}
      http_content = details[:file]&.gsub(no_protocol_file_contents, "/")
      https_content = secure_details[:file]&.gsub(no_protocol_file_contents, "/")

      # Check for the same content after removing all protocols
      if (http_content && https_content) && (http_content == https_content) &&
         url.start_with?("http://") && secure_details[:final_url]&.start_with?("https://")
        return "The #{url_type} #{url} should use HTTPS rather than HTTP"
      end

      return unless strict

      # Same size, different content after normalization
      # (typical causes: Generated ID, Timestamp, Unix time)
      if http_content.length == https_content.length
        return "The #{url_type} #{url} may be able to use HTTPS rather than HTTP. Please verify it in a browser."
      end

      lenratio = (100 * https_content.length / http_content.length).to_i
      return unless (90..110).cover?(lenratio)

      "The #{url_type} #{url} may be able to use HTTPS rather than HTTP. Please verify it in a browser."
    end

    def curl_http_content_headers_and_checksum(url, specs: {}, hash_needed: false, user_agent: :default)
      file = Tempfile.new.tap(&:close)

      specs = specs.flat_map { |option, argument| ["--#{option.to_s.tr("_", "-")}", argument] }
      max_time = hash_needed ? "600" : "25"
      output, _, status = curl_output(
        *specs, "--dump-header", "-", "--output", file.path, "--location",
        "--connect-timeout", "15", "--max-time", max_time, "--retry-max-time", max_time, url,
        user_agent: user_agent
      )

      if status.success?
        parsed_output = parse_curl_output(output)
        heads = parsed_output[:heads]
        if heads.present?
          status_code = curl_response_status_code(heads)
          final_url = curl_response_last_location(heads)

          headers = heads.last[:headers]
          etag = headers["etag"][%r{^([wW]/)?"(([^"]|\\")*)"}, 2] if headers["etag"]
          content_length = headers["content-length"]
        end

        file_contents = File.read(file.path)
        file_hash = Digest::SHA2.hexdigest(file_contents) if hash_needed
      end

      {
        url:            url,
        final_url:      final_url,
        headers:        headers,
        status:         status_code,
        etag:           etag,
        content_length: content_length,
        file:           file_contents,
        file_hash:      file_hash,
      }
    ensure
      file.unlink
    end

    def http_status_ok?(status)
      (100..299).cover?(status.to_i)
    end

    # Separates the output text from `curl` into an array of response heads and
    # the final response body.
    # @param output [String] The output text from `curl` containing
    #   response head(s), body, or both.
    # @return [Hash] A hash containing an array of the response heads and the
    #   body output, if found.
    def parse_curl_output(output)
      heads = []
      return { heads: heads, body: "" } unless output.is_a?(String)

      output = output.lstrip
      while output.match?(%r{\AHTTP/[\d.]+ \d+})
        head_text, _, output = output.partition("\r\n\r\n")
        output = output.lstrip
        next if head_text.blank?

        head_text.chomp!
        head = parse_curl_head(head_text)
        heads << head if head.present?
      end

      { heads: heads, body: output }
    end

    # Parses a `curl` response head into a hash containing the status
    # information and headers.
    # @param head_text [String] The head text of a `curl` response.
    # @return [Hash] A hash containing the status information and headers
    #   (as a hash with header names as keys).
    def parse_curl_head(head_text)
      head = {}
      return head if !head_text.is_a?(String) || !head_text.match?(%r{^HTTP/.* (?<code>\d+)(?: (?<desc>[^\r\n]+))?})

      # Parse and remove the status line
      match = head_text.match(%r{^HTTP/.* (?<code>\d+)(?: (?<desc>[^\r\n]+))?})
      head[:status_code] = match["code"] if match["code"]
      head[:status_desc] = match["desc"] if match["desc"]
      head_text = head_text.sub(%r{^HTTP/.* (\d+).*$\s*}, "")

      # Create a hash from the headers
      head[:headers] = head_text.split("\r\n")
                                .map { |header| header.split(/:\s*/, 2) }
                                .to_h.transform_keys(&:downcase)

      head
    end

    # Returns the status code of the last response from cURL output.
    # @param heads [Array<Hash>] An array of hashes containing response status
    #   information and headers from `parse_curl_head`.
    # @return [String, nil] The status code of the last response.
    def curl_response_status_code(heads)
      return unless heads.is_a?(Array)
      return unless heads.last.is_a?(Hash)

      heads.last[:status_code]
    end

    # Returns the URL from the last location header found in cURL output
    # response heads.
    # @param heads [Array<Hash>] An array of hashes containing response status
    #   information and headers from `parse_curl_head`.
    # @param url [String, nil] The URL to use as a base for making the
    #  `location` URL absolute.
    # @param absolutize [true, false] Whether to make the location URL absolute.
    # @return [String, nil] The URL from last-occurring `location` header, if
    #   any, in the responses.
    def curl_response_last_location(heads, url: nil, absolutize: false)
      return unless heads.is_a?(Array)

      heads.reverse_each do |head|
        next if !head[:headers] || !(location = head[:headers]["location"])

        return (absolutize && url.is_a?(String)) ? URI.join(url, location).to_s : location
      end

      nil
    end
  end
end

# FIXME: Include `Utils::Curl` explicitly everywhere it is used.
include Utils::Curl # rubocop:disable Style/MixinUsage
