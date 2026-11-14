# typed: strict
# frozen_string_literal: true

module Utils
  module Curl
    # Parse HTTP responses and resolve redirect locations from curl output.
    module Responses
      extend T::Helpers

      requires_ancestor { Kernel }

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

          location = Array(response[:headers]["location"]).last
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

          location = Array(response[:headers]["location"]).last
          next if location.blank?

          base_url = URI.join(base_url, location).to_s
        end

        base_url
      end

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
        response_text = response_text.sub(%r{^HTTP/.* \d+.*$\s*}, "")

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
end
