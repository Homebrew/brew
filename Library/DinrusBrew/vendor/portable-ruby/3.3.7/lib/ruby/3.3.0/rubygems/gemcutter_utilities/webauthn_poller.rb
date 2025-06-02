# frozen_string_literal: true

##
# The WebauthnPoller class retrieves an OTP after a user successfully WebAuthns. An instance
# polls the Gem host for the OTP code. The polling request (api/v1/webauthn_verification/<webauthn_token>/status.json)
# is sent to the Gem host every 5 seconds and will timeout after 5 minutes. If the status field in the json response
# is "success", the code field will contain the OTP code.
#
# Example usage:
#
#   thread = Gem::WebauthnPoller.poll_thread(
#     {},
#     "RubyGems.org",
#     "https://rubygems.org/api/v1/webauthn_verification/odow34b93t6aPCdY",
#     { email: "email@example.com", password: "password" }
#   )
#   thread.join
#   otp = thread[:otp]
#   error = thread[:error]
#

module Gem::GemcutterUtilities
  class WebauthnPoller
    include Gem::GemcutterUtilities
    TIMEOUT_IN_SECONDS = 300

    attr_reader :options, :host

    def initialize(options, host)
      @options = options
      @host = host
    end

    def self.poll_thread(options, host, webauthn_url, credentials)
      Thread.new do
        thread = Thread.current
        thread.abort_on_exception = true
        thread.report_on_exception = false
        thread[:otp] = new(options, host).poll_for_otp(webauthn_url, credentials)
      rescue Gem::WebauthnVerificationError, Gem::Timeout::Error => e
        thread[:error] = e
      end
    end

    def poll_for_otp(webauthn_url, credentials)
      Gem::Timeout.timeout(TIMEOUT_IN_SECONDS) do
        loop do
          response = webauthn_verification_poll_response(webauthn_url, credentials)
          raise Gem::WebauthnVerificationError, response.message unless response.is_a?(Gem::Net::HTTPSuccess)

          require "json"
          parsed_response = JSON.parse(response.body)
          case parsed_response["status"]
          when "pending"
            sleep 5
          when "success"
            return parsed_response["code"]
          else
            raise Gem::WebauthnVerificationError, parsed_response.fetch("message", "Invalid response from server")
          end
        end
      end
    end

    private

    def webauthn_verification_poll_response(webauthn_url, credentials)
      webauthn_token = %r{(?<=\/)[^\/]+(?=$)}.match(webauthn_url)[0]
      rubygems_api_request(:get, "api/v1/webauthn_verification/#{webauthn_token}/status.json") do |request|
        if credentials.empty?
          request.add_field "Authorization", api_key
        elsif credentials[:identifier] && credentials[:password]
          request.basic_auth credentials[:identifier], credentials[:password]
        else
          raise Gem::WebauthnVerificationError, "Provided missing credentials"
        end
      end
    end
  end
end
