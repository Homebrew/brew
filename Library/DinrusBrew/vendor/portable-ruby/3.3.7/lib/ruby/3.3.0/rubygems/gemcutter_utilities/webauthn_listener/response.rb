# frozen_string_literal: true

##
# The WebauthnListener Response class is used by the WebauthnListener to create
# responses to be sent to the Gem host. It creates a Gem::Net::HTTPResponse instance
# when initialized and can be converted to the appropriate format to be sent by a socket using `to_s`.
# Gem::Net::HTTPResponse instances cannot be directly sent over a socket.
#
# Types of response classes:
#   - OkResponse
#   - NoContentResponse
#   - BadRequestResponse
#   - NotFoundResponse
#   - MethodNotAllowedResponse
#
# Example usage:
#
#   server = TCPServer.new(0)
#   socket = server.accept
#
#   response = OkResponse.for("https://rubygems.example")
#   socket.print response.to_s
#   socket.close
#

module Gem::GemcutterUtilities
  class WebauthnListener
    class Response
      attr_reader :http_response

      def self.for(host)
        new(host)
      end

      def initialize(host)
        @host = host

        build_http_response
      end

      def to_s
        status_line = "HTTP/#{@http_response.http_version} #{@http_response.code} #{@http_response.message}\r\n"
        headers = @http_response.to_hash.map {|header, value| "#{header}: #{value.join(", ")}\r\n" }.join + "\r\n"
        body = @http_response.body ? "#{@http_response.body}\n" : ""

        status_line + headers + body
      end

      private

      # Must be implemented in subclasses
      def code
        raise NotImplementedError
      end

      def reason_phrase
        raise NotImplementedError
      end

      def body; end

      def build_http_response
        response_class = Gem::Net::HTTPResponse::CODE_TO_OBJ[code.to_s]
        @http_response = response_class.new("1.1", code, reason_phrase)
        @http_response.instance_variable_set(:@read, true)

        add_connection_header
        add_access_control_headers
        add_body
      end

      def add_connection_header
        @http_response["connection"] = "close"
      end

      def add_access_control_headers
        @http_response["access-control-allow-origin"] = @host
        @http_response["access-control-allow-methods"] = "POST"
        @http_response["access-control-allow-headers"] = %w[Content-Type Authorization x-csrf-token]
      end

      def add_body
        return unless body
        @http_response["content-type"] = "text/plain; charset=utf-8"
        @http_response["content-length"] = body.bytesize
        @http_response.instance_variable_set(:@body, body)
      end
    end

    class OkResponse < Response
      private

      def code
        200
      end

      def reason_phrase
        "OK"
      end

      def body
        "success"
      end
    end

    class NoContentResponse < Response
      private

      def code
        204
      end

      def reason_phrase
        "No Content"
      end
    end

    class BadRequestResponse < Response
      private

      def code
        400
      end

      def reason_phrase
        "Bad Request"
      end

      def body
        "missing code parameter"
      end
    end

    class NotFoundResponse < Response
      private

      def code
        404
      end

      def reason_phrase
        "Not Found"
      end
    end

    class MethodNotAllowedResponse < Response
      private

      def code
        405
      end

      def reason_phrase
        "Method Not Allowed"
      end

      def add_access_control_headers
        super
        @http_response["allow"] = %w[GET OPTIONS]
      end
    end
  end
end
