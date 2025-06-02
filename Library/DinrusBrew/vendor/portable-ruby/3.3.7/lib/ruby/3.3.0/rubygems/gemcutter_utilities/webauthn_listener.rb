# frozen_string_literal: true

require_relative "webauthn_listener/response"

##
# The WebauthnListener class retrieves an OTP after a user successfully WebAuthns with the Gem host.
# An instance opens a socket using the TCPServer instance given and listens for a request from the Gem host.
# The request should be a GET request to the root path and contains the OTP code in the form
# of a query parameter `code`. The listener will return the code which will be used as the OTP for
# API requests.
#
# Types of responses sent by the listener after receiving a request:
#   - 200 OK: OTP code was successfully retrieved
#   - 204 No Content: If the request was an OPTIONS request
#   - 400 Bad Request: If the request did not contain a query parameter `code`
#   - 404 Not Found: The request was not to the root path
#   - 405 Method Not Allowed: OTP code was not retrieved because the request was not a GET/OPTIONS request
#
# Example usage:
#
#   thread = Gem::WebauthnListener.listener_thread("https://rubygems.example", server)
#   thread.join
#   otp = thread[:otp]
#   error = thread[:error]
#

module Gem::GemcutterUtilities
  class WebauthnListener
    attr_reader :host

    def initialize(host)
      @host = host
    end

    def self.listener_thread(host, server)
      Thread.new do
        thread = Thread.current
        thread.abort_on_exception = true
        thread.report_on_exception = false
        thread[:otp] = new(host).wait_for_otp_code(server)
      rescue Gem::WebauthnVerificationError => e
        thread[:error] = e
      ensure
        server.close
      end
    end

    def wait_for_otp_code(server)
      loop do
        socket = server.accept
        request_line = socket.gets

        method, req_uri, _protocol = request_line.split(" ")
        req_uri = Gem::URI.parse(req_uri)

        responder = SocketResponder.new(socket)

        unless root_path?(req_uri)
          responder.send(NotFoundResponse.for(host))
          raise Gem::WebauthnVerificationError, "Page at #{req_uri.path} not found."
        end

        case method.upcase
        when "OPTIONS"
          responder.send(NoContentResponse.for(host))
          next # will be GET
        when "GET"
          if otp = parse_otp_from_uri(req_uri)
            responder.send(OkResponse.for(host))
            return otp
          end
          responder.send(BadRequestResponse.for(host))
          raise Gem::WebauthnVerificationError, "Did not receive OTP from #{host}."
        else
          responder.send(MethodNotAllowedResponse.for(host))
          raise Gem::WebauthnVerificationError, "Invalid HTTP method #{method.upcase} received."
        end
      end
    end

    private

    def root_path?(uri)
      uri.path == "/"
    end

    def parse_otp_from_uri(uri)
      require "cgi"

      return if uri.query.nil?
      CGI.parse(uri.query).dig("code", 0)
    end

    class SocketResponder
      def initialize(socket)
        @socket = socket
      end

      def send(response)
        @socket.print response.to_s
        @socket.close
      end
    end
  end
end
