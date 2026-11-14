# frozen_string_literal: true

# Copyright 2024 The Sigstore Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module Sigstore
  module OIDC
    KNOWN_OIDC_ISSUERS = {
      "https://accounts.google.com" => "email",
      "https://oauth2.sigstore.dev/auth" => "email",
      "https://oauth2.sigstage.dev/auth" => "email",
      "https://token.actions.githubusercontent.com" => "job_workflow_ref"
    }.freeze
    private_constant :KNOWN_OIDC_ISSUERS

    DEFAULT_AUDIENCE = "sigstore"
    private_constant :DEFAULT_AUDIENCE

    class IdentityToken
      attr_reader :raw_token, :identity

      def initialize(raw_token)
        @raw_token = raw_token

        @unverified_claims = self.class.decode_jwt(raw_token)
        @iss = @unverified_claims["iss"]
        @nbf = @unverified_claims["nbf"]
        @exp = @unverified_claims["exp"]

        # fail early if this token isn't within its validity period
        raise Error::InvalidIdentityToken, "identity token is not within its validity period" unless in_validity_period?

        if (identity_claim = KNOWN_OIDC_ISSUERS[issuer])
          unless @unverified_claims[identity_claim]
            raise Error::InvalidIdentityToken, "identity token is missing required claim: #{identity_claim}"
          end

          @identity = @unverified_claims[identity_claim]
          # https://github.com/sigstore/fulcio/blob/8311f93c01ea5b068a86d37c4bb51573289bfd69/pkg/identity/github/principal.go#L92
          @identity = "https://github.com/#{@identity}" if issuer == "https://token.actions.githubusercontent.com"
        else
          @identity = @unverified_claims["sub"]
        end
      end

      def issuer
        @iss
      end

      def self.decode_jwt(raw_token)
        # These claims are required by OpenID Connect, so
        # we can strongly enforce their presence.
        # See: https://openid.net/specs/openid-connect-basic-1_0.html#IDToken
        required = %w[aud sub iat exp iss]
        audience = DEFAULT_AUDIENCE
        leeway = 5

        _header, payload, _signature =
          raw_token
          .split(".", 3)
          .tap do |parts|
            raise Error::InvalidIdentityToken, "identity token is not a JWT" unless parts.length == 3
          end.map! do |part| # rubocop:disable Style/MultilineBlockChain
            part.unpack1("m*")
          rescue ArgumentError
            raise Error::InvalidIdentityToken, "Invalid base64 in identity token"
          end

        begin
          payload = JSON.parse(payload)
        rescue JSON::ParserError
          raise Error::InvalidIdentityToken, "Invalid JSON in identity token"
        end
        unless payload.is_a?(Hash)
          raise Error::InvalidIdentityToken,
                "Invalid JSON in identity token: must be a json object"
        end
        time = Time.now.to_i
        validate_required_claims(payload, required)
        validate_iat(payload["iat"], time, leeway)
        validate_nbf(payload["nbf"], time, leeway)
        validate_exp(payload["exp"], time, leeway)
        validate_aud(payload["aud"], audience)

        payload
      end

      private

      # Returns whether or not this `Identity` is currently within its self-stated validity period.
      def in_validity_period?
        now = Time.now.utc.to_i
        return false if @nbf && @nbf > now

        now < @exp
      end

      class << self
        private

        def validate_required_claims(payload, required)
          required.each do |claim|
            next if payload[claim]

            raise Error::InvalidIdentityToken, "Missing required claim in identity token: #{claim}"
          end
        end

        def validate_iat(iat, now, leeway)
          raise Error::InvalidIdentityToken, "iat claim must be an integer" unless iat.is_a?(Integer)
          raise Error::InvalidIdentityToken, "iat claim is in the future" if iat > now + leeway
        end

        def validate_nbf(nbf, now, leeway)
          # The nbf ("not before") claim is optional (RFC 7519); skip validation when absent.
          return if nbf.nil?

          raise Error::InvalidIdentityToken, "nbf claim must be an integer" unless nbf.is_a?(Integer)
          raise Error::InvalidIdentityToken, "nbf claim is in the future" if nbf > now + leeway
        end

        def validate_exp(exp, now, leeway)
          raise Error::InvalidIdentityToken, "exp claim must be an integer" unless exp.is_a?(Integer)
          raise Error::InvalidIdentityToken, "exp claim is in the past" if exp <= now - leeway
        end

        def validate_aud(aud, audience)
          aud = Array(aud)

          raise Error::InvalidIdentityToken, "aud claim must not be empty" if aud.empty?
          raise Error::InvalidIdentityToken, "aud claim must be strings" unless aud.all?(String)

          return if aud.include?(audience)

          raise Error::InvalidIdentityToken,
                "aud claim does not contain the expected audience #{audience.inspect}"
        end
      end
    end
  end
end
