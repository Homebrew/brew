# frozen_string_literal: true

module Bundler
  class Fetcher
    class Downloader
      attr_reader :connection
      attr_reader :redirect_limit

      def initialize(connection, redirect_limit)
        @connection = connection
        @redirect_limit = redirect_limit
      end

      def fetch(uri, headers = {}, counter = 0)
        raise HTTPError, "Too many redirects" if counter >= redirect_limit

        filtered_uri = URICredentialsFilter.credential_filtered_uri(uri)

        response = request(uri, headers)
        Bundler.ui.debug("HTTP #{response.code} #{response.message} #{filtered_uri}")

        case response
        when Gem::Net::HTTPSuccess, Gem::Net::HTTPNotModified
          response
        when Gem::Net::HTTPRedirection
          new_uri = Gem::URI.parse(response["location"])
          if new_uri.host == uri.host
            new_uri.user = uri.user
            new_uri.password = uri.password
          end
          fetch(new_uri, headers, counter + 1)
        when Gem::Net::HTTPRequestedRangeNotSatisfiable
          new_headers = headers.dup
          new_headers.delete("Range")
          new_headers["Accept-Encoding"] = "gzip"
          fetch(uri, new_headers)
        when Gem::Net::HTTPRequestEntityTooLarge
          raise FallbackError, response.body
        when Gem::Net::HTTPTooManyRequests
          raise TooManyRequestsError, response.body
        when Gem::Net::HTTPUnauthorized
          raise BadAuthenticationError, uri.host if uri.userinfo
          raise AuthenticationRequiredError, uri.host
        when Gem::Net::HTTPForbidden
          raise AuthenticationForbiddenError, uri.host
        when Gem::Net::HTTPNotFound
          raise FallbackError, "Gem::Net::HTTPNotFound: #{filtered_uri}"
        else
          message = "Gem::#{response.class.name.gsub(/\AGem::/, "")}"
          message += ": #{response.body}" unless response.body.empty?
          raise HTTPError, message
        end
      end

      def request(uri, headers)
        validate_uri_scheme!(uri)

        filtered_uri = URICredentialsFilter.credential_filtered_uri(uri)

        Bundler.ui.debug "HTTP GET #{filtered_uri}"
        req = Gem::Net::HTTP::Get.new uri.request_uri, headers
        if uri.user
          user = CGI.unescape(uri.user)
          password = uri.password ? CGI.unescape(uri.password) : nil
          req.basic_auth(user, password)
        end
        connection.request(uri, req)
      rescue OpenSSL::SSL::SSLError
        raise CertificateFailureError.new(uri)
      rescue *HTTP_ERRORS => e
        Bundler.ui.trace e
        if e.is_a?(SocketError) || e.message.to_s.include?("host down:")
          raise NetworkDownError, "Could not reach host #{uri.host}. Check your network " \
            "connection and try again."
        else
          raise HTTPError, "Network error while fetching #{filtered_uri}" \
            " (#{e})"
        end
      end

      private

      def validate_uri_scheme!(uri)
        return if /\Ahttps?\z/.match?(uri.scheme)
        raise InvalidOption,
          "The request uri `#{uri}` has an invalid scheme (`#{uri.scheme}`). " \
          "Did you mean `http` or `https`?"
      end
    end
  end
end
