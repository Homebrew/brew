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
        when Net::HTTPSuccess, Net::HTTPNotModified
          response
        when Net::HTTPRedirection
          new_uri = Bundler::URI.parse(response["location"])
          if new_uri.host == uri.host
            new_uri.user = uri.user
            new_uri.password = uri.password
          end
          fetch(new_uri, headers, counter + 1)
        when Net::HTTPRequestedRangeNotSatisfiable
          new_headers = headers.dup
          new_headers.delete("Range")
          new_headers["Accept-Encoding"] = "gzip"
          fetch(uri, new_headers)
        when Net::HTTPRequestEntityTooLarge
          raise FallbackError, response.body
        when Net::HTTPTooManyRequests
          raise TooManyRequestsError, response.body
        when Net::HTTPUnauthorized
          raise BadAuthenticationError, uri.host if uri.userinfo
          raise AuthenticationRequiredError, uri.host
        when Net::HTTPNotFound
          raise FallbackError, "Net::HTTPNotFound: #{filtered_uri}"
        else
          raise HTTPError, "#{response.class}#{": #{response.body}" unless response.body.empty?}"
        end
      end

      def request(uri, headers)
        validate_uri_scheme!(uri)

        filtered_uri = URICredentialsFilter.credential_filtered_uri(uri)

        Bundler.ui.debug "HTTP GET #{filtered_uri}"
        req = Net::HTTP::Get.new uri.request_uri, headers
        if uri.user
          user = CGI.unescape(uri.user)
          password = uri.password ? CGI.unescape(uri.password) : nil
          req.basic_auth(user, password)
        end
        connection.request(uri, req)
      rescue NoMethodError => e
        raise unless ["undefined method", "use_ssl="].all? {|snippet| e.message.include? snippet }
        raise LoadError.new("cannot load such file -- openssl")
      rescue OpenSSL::SSL::SSLError
        raise CertificateFailureError.new(uri)
      rescue *HTTP_ERRORS => e
        Bundler.ui.trace e
        if e.is_a?(SocketError) || e.message =~ /host down:/
          raise NetworkDownError, "Could not reach host #{uri.host}. Check your network " \
            "connection and try again."
        else
          raise HTTPError, "Network error while fetching #{filtered_uri}" \
            " (#{e})"
        end
      end

      private

      def validate_uri_scheme!(uri)
        return if uri.scheme =~ /\Ahttps?\z/
        raise InvalidOption,
          "The request uri `#{uri}` has an invalid scheme (`#{uri.scheme}`). " \
          "Did you mean `http` or `https`?"
      end
    end
  end
end
