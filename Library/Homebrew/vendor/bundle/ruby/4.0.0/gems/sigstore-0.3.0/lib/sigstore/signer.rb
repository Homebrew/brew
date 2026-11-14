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

require "protobug_in_toto_attestation_protos"

require_relative "internal/util"
require_relative "internal/x509"
require_relative "models"
require_relative "oidc"
require_relative "policy"
require_relative "verifier"
require_relative "version"

module Sigstore
  class Signer
    include Loggable

    STATEMENT_REGISTRY = Protobug::Registry.new do |registry|
      InTotoAttestation::V1.register_statement_protos(registry)
    end

    def initialize(jwt:, trusted_root:, signing_config: nil)
      @identity_token = OIDC::IdentityToken.new(jwt)
      @trusted_root = trusted_root
      @signing_config = signing_config

      @verifier = Verifier.for_trust_root(trust_root: @trusted_root)
    end

    IN_TOTO_PAYLOAD_TYPE = "application/vnd.in-toto+json"

    def sign(payload)
      keypair, leaf = issue_signing_certificate

      # Sign the payload, then submit a hash of the signature to the TSA and the
      # signing metadata (a hashedrekord) to the transparency log.
      signature = sign_payload(payload, keypair)
      timestamp_verification_data = submit_signature_hash_to_timstamping_service(signature)

      hashed_input = Common::V1::HashOutput.new
      hashed_input.algorithm = Common::V1::HashAlgorithm::SHA2_256
      hashed_input.digest = OpenSSL::Digest("SHA256").digest(payload)
      tlog_entry = submit_message_signature_entry(signature, leaf, hashed_input)

      bundle = collect_bundle(leaf, [tlog_entry], timestamp_verification_data, hashed_input, signature)
      verify(payload, bundle)

      bundle
    end

    # Sign +payload+ (an in-toto statement) as a DSSE envelope, returning a
    # bundle whose content is the envelope rather than a message signature.
    def sign_dsse(payload, payload_type: IN_TOTO_PAYLOAD_TYPE)
      keypair, leaf = issue_signing_certificate

      # DSSE signs the Pre-Authentication Encoding of the payload, not the
      # payload itself.
      pae = Internal::Util.dsse_pae(payload_type, payload)
      signature = sign_payload(pae, keypair)
      envelope = build_dsse_envelope(payload, payload_type, signature)

      timestamp_verification_data = submit_signature_hash_to_timstamping_service(signature)
      tlog_entry = submit_dsse_entry(envelope, leaf, pae)

      bundle = collect_dsse_bundle(leaf, [tlog_entry], timestamp_verification_data, envelope)
      verify_dsse_statement(payload, bundle)

      bundle
    end

    private

    # Generate an ephemeral keypair, obtain a Fulcio signing certificate bound to
    # the identity token, and verify the returned chain. Shared by all signing
    # flows; returns [keypair, leaf_certificate].
    def issue_signing_certificate
      keypair = generate_keypair
      csr = generate_csr(keypair)
      leaf = fetch_cert(csr)
      verify_chain(leaf)
      [keypair, leaf]
    end

    def generate_keypair
      # maybe allow configuring?
      key = OpenSSL::PKey::EC.generate("prime256v1")
      logger.debug { "Generated keypair #{key}" }
      key
    end

    def generate_csr(keypair)
      csr = OpenSSL::X509::Request.new

      # The subject is unused, but must be set to avoid an error on JRuby
      csr.subject = OpenSSL::X509::Name.new
      csr.public_key = keypair

      # The subject in the CertificationRequestInfo is an X.501 RelativeDistinguishedName.
      # The value of the RelativeDistinguishedName SHOULD be the subject of the authentication token;
      # its type MUST be the type identified in the Fulcio instance’s public configuration.
      # NOTE: the subject of the CSR is unused

      extension = OpenSSL::X509::ExtensionFactory.new.create_extension(
        "basicConstraints",
        "CA:FALSE",
        true # critical
      )
      csr.add_attribute OpenSSL::X509::Attribute.new(
        "extReq",
        OpenSSL::ASN1::Set.new(
          [OpenSSL::ASN1::Sequence.new([extension])]
        )
      )

      csr.sign keypair, OpenSSL::Digest.new("SHA256")

      logger.debug { "Generated CSR" }

      {
        credentials: {
          oidcIdentityToken: @identity_token.raw_token
        },
        certificateSigningRequest: Internal::Util.base64_encode(csr.to_pem)
      }
    end

    def fulcio_url
      return @signing_config.fulcio.url if @signing_config

      @trusted_root.certificate_authority_for_signing.uri
    end

    def fetch_cert(csr)
      uri = URI.parse fulcio_url
      uri = URI.join(uri, "api/v2/signingCert")
      resp = Net::HTTP.post(
        uri,
        JSON.dump(csr),
        { "Content-Type" => "application/json", "User-Agent" => Sigstore::USER_AGENT }
      )

      unless resp.code == "200"
        raise Error::Signing,
              "#{resp.code} #{resp.message}\n\n#{resp.body}"
      end

      resp_body = JSON.parse(resp.body)

      unless resp_body.key?("signedCertificateEmbeddedSct")
        raise Error::Signing, "missing signedCertificateEmbeddedSct in response from fulcio"
      end

      cert = resp_body.fetch("signedCertificateEmbeddedSct").fetch("chain")
                      .fetch("certificates").first.then { |pem| Internal::X509::Certificate.read(pem) }
      logger.debug { "Fetched cert from fulcio" }
      cert
    end

    def verify_chain(leaf)
      # Perform certification path validation (RFC 5280 §6) of the returned certificate chain with the pre-distributed
      # Fulcio root certificate(s) as a trust anchor.

      now = Time.now
      if leaf.not_before > now
        unless leaf.not_before - now < 60
          raise Error::Signing, "leaf certificate not yet valid: #{leaf.not_before.inspect} vs #{now.inspect}"
        end

        logger.warn do
          "leaf certificate not yet valid: #{leaf.not_before.inspect} vs #{now.inspect}, sleeping until valid"
        end
        sleep(leaf.not_before - now)
      end

      chain, err = Internal::X509.validate_chain(@trusted_root.fulcio_cert_chains, leaf, nil)
      raise Error::Signing, "failed to validate returned certificate chain: #{err.reason}" if err

      logger.debug { "verified chain" }

      # Extract a SignedCertificateTimestamp, which may be embedded as an X.509 extension in the leaf certificate or
      # attached separately in the SigningCertificate returned from the Identity Service.
      # Verify this SignedCertificateTimestamp as in RFC 9162 §8.1.3, using the root certificate from
      # the Certificate Transparency Log.
      if (result = @verifier.verify_scts(leaf, chain)) && !result.verified?
        raise Error::Signing, "Failed to verify SCTs: #{result.reason}"
      end

      # Check that the leaf certificate contains the subject from the certificate signing request and encodes the
      # appropriate AuthenticationServiceIdentifier in an extension with OID 1.3.6.1.4.1.57264.1.8.

      fulcio_issuer = leaf.extension(Internal::X509::Extension::FulcioIssuer)
      unless fulcio_issuer && fulcio_issuer.issuer == @identity_token.issuer
        raise Error::Signing, "certificate does not contain expected Fulcio issuer"
      end

      unless leaf.subject.to_a.empty?
        raise Error::Signing,
              "certificate contains unexpected subject #{leaf.subject.to_a}"
      end

      general_names = leaf.extension(Internal::X509::Extension::SubjectAlternativeName).general_names
      expected_san = [@identity_token.identity]
      if general_names.map(&:last) != expected_san
        raise Error::Signing,
              "certificate does not contain expected SAN #{expected_san}, got #{general_names}"
      end

      [leaf, chain.unshift(leaf)]
    end

    def sign_payload(payload, key)
      # The Signer MAY pre-hash the payload using a hash algorithm from the registry (Spec: Sigstore Registries) for
      # compatibility with some signing metadata formats (see §Submission of Signing Metadata to Transparency Service).
      key.sign("SHA256", payload)
    end

    def submit_signature_hash_to_timstamping_service(signature)
      # The Signer sends a hash of the signature as the messageImprint in a TimeStampReq to the Timestamping Service and
      # receives a TimeStampResp including a `TimeStampToken`.
      # The signer MUST verify the TimeStampToken against the payload and Timestamping Service root certificate.
      #
      # Timestamping is driven by the signing config: a Rekor v2 entry carries no
      # integrated time, so a TSA timestamp is the only trusted signing time. The
      # returned tokens are verified below in #verify (against the trusted root).
      tsa_urls = @signing_config&.tsa_urls || []
      return nil if tsa_urls.empty?

      timestamps = tsa_urls.map { |url| request_timestamp(url, signature) }

      Bundle::V1::TimestampVerificationData.new.tap do |data|
        data.rfc3161_timestamps = timestamps
      end
    end

    def request_timestamp(url, signature)
      # The message imprint is a hash of the signature (RFC 3161 §2.4.1); the
      # Verifier binds the timestamp back to the bundle signature via this imprint.
      req = OpenSSL::Timestamp::Request.new
      req.algorithm = "SHA256"
      req.message_imprint = OpenSSL::Digest::SHA256.digest(signature)
      req.cert_requested = true
      req.version = 1
      req.nonce = OpenSSL::BN.rand(64)

      uri = URI.parse(url)
      resp = Net::HTTP.post(
        uri, req.to_der,
        { "Content-Type" => "application/timestamp-query", "User-Agent" => Sigstore::USER_AGENT }
      )
      unless resp.code == "200"
        raise Error::InvalidTimestamp, "TSA #{url} returned #{resp.code} #{resp.message}\n#{resp.body}"
      end

      # Parse the response to fail fast on a malformed token and confirm the TSA
      # actually granted a timestamp (PKIStatus GRANTED / GRANTED_WITH_MODS); a token
      # is only present for those statuses. Cryptographic verification of the token is
      # deferred to the verification step.
      response = OpenSSL::Timestamp::Response.new(resp.body)
      unless [OpenSSL::Timestamp::Response::GRANTED,
              OpenSSL::Timestamp::Response::GRANTED_WITH_MODS].include?(response.status)
        raise Error::InvalidTimestamp,
              "TSA #{url} did not grant a timestamp (status #{response.status}): #{response.status_text.inspect}"
      end

      Common::V1::RFC3161SignedTimestamp.new.tap do |ts|
        ts.signed_timestamp = resp.body
      end
    end

    def build_proposed_hashed_rekord_entry(signature, cert, hashed_input)
      algorithm = case hashed_input.algorithm
                  when Common::V1::HashAlgorithm::SHA2_256 then "sha256"
                  when Common::V1::HashAlgorithm::SHA2_384 then "sha384"
                  when Common::V1::HashAlgorithm::SHA2_512 then "sha512"
                  else
                    raise ArgumentError,
                          "unsupported hash algorithm: #{hashed_input.algorithm.inspect}"
                  end
      {
        "spec" => {
          "signature" => {
            "content" => Internal::Util.base64_encode(signature),
            "publicKey" => {
              "content" => Internal::Util.base64_encode(cert.to_pem)
            }
          },
          "data" => {
            "hash" => {
              "algorithm" => algorithm,
              "value" => Internal::Util.hex_encode(hashed_input.digest)
            }
          }
        },
        "kind" => "hashedrekord",
        "apiVersion" => "0.0.1"
      }
    end

    # Submit a hashedrekord entry for a message signature: the prehash digest of
    # the artifact, signed.
    #
    # The Signer chooses a format for signing metadata; this format MUST be in the supportedMetadataFormats in the
    # Transparency Service configuration. The Signer prepares signing metadata containing at a minimum:
    # * The signature.
    # * The payload (possibly pre-hashed; if so, the entry also includes the identifier of the hash algorithm).
    # * Verification material (signing certificate or verification key).
    #   * If the verification material is a certificate, the client SHOULD upload only the signing certificate and
    #     SHOULD NOT upload the CA certificate chain.
    #
    # The signing metadata might contain additional, application-specific metadata according to the format used.
    # The Signer then canonically encodes the metadata (according to the chosen format).
    def submit_message_signature_entry(signature, cert, hashed_input)
      # A Rekor v2 (tiled) instance speaks a different API and a different entry
      # format (hashedrekord 0.0.2). When the signing config selects one, submit
      # there; otherwise fall back to the v1 hashedrekord flow.
      if rekor_v2?
        request = build_create_entry_request(hashed_input.digest, signature, cert)
        return submit_rekor_v2_entry(request)
      end

      # TODO: allow configuring the entry kind?
      proposed_entry = build_proposed_hashed_rekord_entry(signature, cert, hashed_input)

      ctlog = @trusted_root.tlog_for_signing
      logger.info { "Submitting to #{ctlog.base_url}" }

      # The signer MUST verify the log entry as in Spec: Transparency Service.
      @verifier.rekor_client.log.entries.post(proposed_entry)
    end

    # Submit a transparency log entry for a DSSE envelope. Rekor v1 stores a
    # native `dsse` entry; Rekor v2 stores a hashedrekord over the DSSE PAE (the
    # signed bytes), since v2 only supports the hashedrekord type.
    def submit_dsse_entry(envelope, cert, pae)
      if rekor_v2?
        digest = OpenSSL::Digest::SHA256.digest(pae)
        request = build_create_entry_request(digest, envelope.signatures.first.sig, cert)
        return submit_rekor_v2_entry(request)
      end

      proposed_entry = build_proposed_dsse_entry(envelope, cert)

      ctlog = @trusted_root.tlog_for_signing
      logger.info { "Submitting to #{ctlog.base_url}" }

      @verifier.rekor_client.log.entries.post(proposed_entry)
    end

    def rekor_v2?
      @signing_config && @signing_config.tlog.major_api_version == 2
    end

    def submit_rekor_v2_entry(request)
      tlog_url = @signing_config.tlog.url
      logger.info { "Submitting to #{tlog_url} (Rekor v2)" }

      Rekor::V2Client.new(url: tlog_url).create_entry(request)
    end

    # A Rekor v2 CreateEntryRequest for a hashedrekord 0.0.2 entry. The request
    # carries only the prehash digest and the signature + verifier; the log fills
    # in the data.algorithm (derived from the verifier key details) itself.
    def build_create_entry_request(digest, signature, cert)
      {
        "hashedRekordRequestV002" => {
          "digest" => Internal::Util.base64_encode(digest),
          "signature" => {
            "content" => Internal::Util.base64_encode(signature),
            "verifier" => {
              "x509Certificate" => {
                "rawBytes" => Internal::Util.base64_encode(cert.to_der)
              },
              "keyDetails" => key_details(cert)
            }
          }
        }
      }
    end

    # A Rekor v1 `dsse` 0.0.1 proposed entry: the full DSSE envelope (as JSON)
    # plus the signing certificate as a verifier.
    def build_proposed_dsse_entry(envelope, cert)
      {
        "apiVersion" => "0.0.1",
        "kind" => "dsse",
        "spec" => {
          "proposedContent" => {
            # Rekor expects the envelope as a JSON string nested in the request.
            "envelope" => envelope.to_json,
            "verifiers" => [Internal::Util.base64_encode(cert.to_pem)]
          }
        }
      }
    end

    # The Sigstore PublicKeyDetails enum name for the leaf certificate's key,
    # used as the Rekor v2 verifier key_details. Only the algorithms this signer
    # can produce are mapped.
    def key_details(cert)
      public_key = cert.openssl.public_key
      unless public_key.is_a?(OpenSSL::PKey::EC)
        raise Error::Signing, "unsupported signing key type: #{public_key.class}"
      end

      case public_key.group.curve_name
      when "prime256v1" then "PKIX_ECDSA_P256_SHA_256"
      when "secp384r1" then "PKIX_ECDSA_P384_SHA_384"
      when "secp521r1" then "PKIX_ECDSA_P521_SHA_512"
      else
        raise Error::Signing, "unsupported EC curve: #{public_key.group.curve_name}"
      end
    end

    def verify(artifact, bundle)
      input = Verification::V1::Artifact.new.tap { |a| a.artifact = artifact }
      verify_bundle(input, bundle)
    end

    # Self-verify a freshly-signed DSSE bundle. The in-toto statement's subject
    # is matched against an artifact, so verify against the first subject's
    # SHA2-256 digest (the only artifact reference available at signing time).
    def verify_dsse_statement(statement, bundle)
      statement = InTotoAttestation::V1::Statement.decode_json(statement, registry: STATEMENT_REGISTRY)
      subject = statement.subject.find { |s| s.digest["sha256"] }
      raise Error::Signing, "in-toto statement has no sha256 subject to verify against" unless subject

      input = Verification::V1::Artifact.new.tap { |a| a.artifact_uri = "sha256:#{subject.digest["sha256"]}" }
      verify_bundle(input, bundle)
    end

    def verify_bundle(artifact, bundle)
      verification_input = Verification::V1::Input.new
      verification_input.bundle = bundle
      verification_input.artifact = artifact

      result = @verifier.verify(
        input: VerificationInput.new(verification_input),
        policy: expected_identity,
        offline: false
      )
      raise Error::Signing, "Failed to verify: #{result.reason}" unless result.verified?
    end

    def expected_identity
      Policy::Identity.new(identity: @identity_token.identity, issuer: @identity_token.issuer)
    end

    def collect_bundle(leaf_certificate, tlog_entries, timestamp_verification_data, hashed_input, signature)
      collect_base_bundle(leaf_certificate, tlog_entries, timestamp_verification_data).tap do |bundle|
        bundle.message_signature = Sigstore::Common::V1::MessageSignature.new.tap do |ms|
          ms.message_digest = hashed_input
          ms.signature = signature
        end
      end
    end

    def collect_dsse_bundle(leaf_certificate, tlog_entries, timestamp_verification_data, envelope)
      collect_base_bundle(leaf_certificate, tlog_entries, timestamp_verification_data).tap do |bundle|
        bundle.dsse_envelope = envelope
      end
    end

    def collect_base_bundle(leaf_certificate, tlog_entries, timestamp_verification_data)
      bundle = Bundle::V1::Bundle.new
      bundle.media_type = BundleType::BUNDLE_0_3.media_type
      bundle.verification_material = Bundle::V1::VerificationMaterial.new
      bundle.verification_material.certificate = Common::V1::X509Certificate.new
      bundle.verification_material.certificate.raw_bytes = leaf_certificate.to_der
      bundle.verification_material.tlog_entries = tlog_entries
      bundle.verification_material.timestamp_verification_data = timestamp_verification_data
      bundle
    end

    def build_dsse_envelope(payload, payload_type, signature)
      DSSE::Envelope.new.tap do |envelope|
        envelope.payload = payload
        envelope.payloadType = payload_type
        envelope.signatures = [DSSE::Signature.new.tap { |s| s.sig = signature }]
      end
    end
  end
end
