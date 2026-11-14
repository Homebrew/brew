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

require_relative "error"

require_relative "trusted_root"

module Sigstore
  VerificationResult = Struct.new(:success) do
    # @implements VerificationResult

    alias_method :verified?, :success
  end

  class VerificationSuccess < VerificationResult
    # @implements VerificationSuccess
    def initialize
      super(success: true)
    end
  end

  class VerificationFailure < VerificationResult
    # @implements VerificationFailure
    attr_reader :reason

    def initialize(reason)
      @reason = reason
      super(success: false)
    end
  end

  class BundleType
    include Comparable

    attr_reader :media_type

    def initialize(media_type)
      @media_type = media_type
    end

    BUNDLE_0_1 = new("application/vnd.dev.sigstore.bundle+json;version=0.1")
    BUNDLE_0_2 = new("application/vnd.dev.sigstore.bundle+json;version=0.2")
    BUNDLE_0_3 = new("application/vnd.dev.sigstore.bundle.v0.3+json")

    VERSIONS = [BUNDLE_0_1, BUNDLE_0_2, BUNDLE_0_3].freeze

    def self.from_media_type(media_type)
      case media_type
      when BUNDLE_0_1.media_type
        BUNDLE_0_1
      when BUNDLE_0_2.media_type
        BUNDLE_0_2
      when BUNDLE_0_3.media_type, "application/vnd.dev.sigstore.bundle+json;version=0.3"
        BUNDLE_0_3
      else
        raise Error::InvalidBundle, "Unsupported bundle format: #{media_type.inspect}"
      end
    end

    def <=>(other)
      VERSIONS.index(self) <=> VERSIONS.index(other)
    end
  end

  class VerificationInput < DelegateClass(Verification::V1::Input)
    attr_reader :trusted_root, :sbundle, :hashed_input

    def initialize(*)
      super

      unless bundle.is_a?(Bundle::V1::Bundle)
        raise ArgumentError,
              "bundle must be a #{Bundle::V1::Bundle}, is #{bundle.class}"
      end

      @trusted_root = TrustedRoot.new(artifact_trust_root)
      @sbundle = SBundle.new(bundle)
      if sbundle.message_signature? && !artifact
        raise Error::InvalidVerificationInput, "bundle with message_signature requires an artifact"
      end

      @hashed_input = self.class.hashed_input_for(artifact)

      freeze
    end

    # Derive the SHA2-256 HashOutput the verifier checks signatures and Rekor
    # entries against, from any of the Artifact oneof variants: the raw bytes
    # (:artifact), a "sha256:"-prefixed URI (:artifact_uri), or a typed digest
    # (:artifact_digest, protobuf-specs v0.5.1+).
    def self.hashed_input_for(artifact)
      case artifact.data
      when :artifact_uri
        unless artifact.artifact_uri.start_with?("sha256:")
          raise Error::InvalidVerificationInput,
                "artifact_uri must be prefixed with 'sha256:'"
        end

        Common::V1::HashOutput.new.tap do |hash_output|
          hash_output.algorithm = Common::V1::HashAlgorithm::SHA2_256
          hexdigest = artifact.artifact_uri.split(":", 2).last
          hash_output.digest = Internal::Util.hex_decode(hexdigest)
        end
      when :artifact
        Common::V1::HashOutput.new.tap do |hash_output|
          hash_output.algorithm = Common::V1::HashAlgorithm::SHA2_256
          hash_output.digest = OpenSSL::Digest.new("SHA256").update(artifact.artifact).digest
        end
      when :artifact_digest
        # The rest of the pipeline (message-signature and Rekor digest checks)
        # operates on SHA2-256, so reject other algorithms.
        artifact.artifact_digest.tap do |hash_output|
          unless hash_output.algorithm == Common::V1::HashAlgorithm::SHA2_256
            raise Error::InvalidVerificationInput,
                  "unsupported artifact digest algorithm: #{hash_output.algorithm}"
          end
        end
      else
        raise Error::InvalidVerificationInput, "Unsupported artifact data: #{artifact.data}"
      end
    end
  end

  class SBundle < DelegateClass(Bundle::V1::Bundle)
    attr_reader :bundle_type, :leaf_certificate, :signing_key_hint

    # A bundle whose signing identity is a bare public key (a "managed" /
    # bring-your-own-key signature) rather than a Fulcio-issued certificate.
    # The key itself is supplied out-of-band; the bundle only carries a hint.
    def key_based?
      !@signing_key_hint.nil?
    end

    def initialize(*)
      super
      @bundle_type = BundleType.from_media_type(media_type)
      validate_version!
      freeze
    end

    def self.for_cert_bytes_and_signature(cert_bytes, signature)
      bundle = Bundle::V1::Bundle.new
      bundle.media_type = BundleType::BUNDLE_0_3.media_type
      bundle.verification_material = Bundle::V1::VerificationMaterial.new
      bundle.verification_material.certificate = Common::V1::X509Certificate.new
      bundle.verification_material.certificate.raw_bytes = cert_bytes
      bundle.message_signature = Common::V1::MessageSignature.new
      bundle.message_signature.signature = signature
      new(bundle)
    end

    # +verifier_pem+ is the PEM of the public key the entry should be bound to. For
    # certificate bundles it defaults to the leaf certificate's PEM; for managed-key
    # bundles the caller passes the supplied key's SubjectPublicKeyInfo PEM.
    def expected_tlog_entry(hashed_input, verifier_pem = leaf_certificate&.to_pem)
      case content
      when :message_signature
        expected_hashed_rekord_tlog_entry(hashed_input, verifier_pem)
      when :dsse_envelope
        # The DSSE-v1 (Rekor v1) expected-entry builders embed the signing leaf
        # certificate. Key-based (managed-key) DSSE is only supported on Rekor v2, whose
        # consistency check runs before this method; reaching here without a leaf
        # certificate means a key-based bundle carries a v1 DSSE entry, which we cannot
        # build an expected entry for. Fail cleanly rather than dereferencing a nil cert.
        if leaf_certificate.nil?
          raise Error::InvalidBundle,
                "key-based DSSE bundles are only supported with Rekor v2 entries"
        end

        rekor_entry = verification_material.tlog_entries.first
        canonicalized_body = begin
          JSON.parse(rekor_entry.canonicalized_body)
        rescue JSON::ParserError
          raise Error::InvalidBundle, "expected canonicalized_body to be JSON"
        end

        case kind_version = canonicalized_body.values_at("kind", "apiVersion")
        when %w[dsse 0.0.1]
          expected_dsse_0_0_1_tlog_entry(verifier_pem)
        when %w[intoto 0.0.2]
          expected_intoto_0_0_2_tlog_entry(verifier_pem)
        else
          raise Error::InvalidRekorEntry, "Unhandled rekor entry kind/version: #{kind_version.inspect}"
        end
      else
        raise Error::InvalidBundle, "expected either message_signature or dsse_envelope"
      end
    end

    private

    def validate_version!
      raise Error::InvalidBundle, "bundle requires verification material" unless verification_material

      case bundle_type
      when BundleType::BUNDLE_0_1
        unless verification_material.tlog_entries.all?(&:inclusion_promise)
          raise Error::InvalidBundle,
                "bundle v0.1 requires an inclusion promise"
        end
        if verification_material.tlog_entries.any? { |t| t.inclusion_proof&.checkpoint.nil? }
          raise Error::InvalidBundle,
                "0.1 bundle contains an inclusion proof without checkpoint"
        end
      else
        unless verification_material.tlog_entries.all?(&:inclusion_proof)
          raise Error::InvalidBundle,
                "must contain an inclusion proof"
        end
        unless verification_material.tlog_entries.all? { |t| t.inclusion_proof.checkpoint&.envelope }
          raise Error::InvalidBundle,
                "inclusion proof must contain a checkpoint"
        end
      end

      raise Error::InvalidBundle, "Expected one tlog entry" if verification_material.tlog_entries.size > 1

      case verification_material.content
      when :public_key
        # Managed key: the verifying key is provided out-of-band; the bundle only
        # carries a hint identifying it. There is no certificate to anchor.
        @signing_key_hint = verification_material.public_key.hint
        return
      when :x509_certificate_chain
        certs = verification_material.x509_certificate_chain.certificates.map do |cert|
          Internal::X509::Certificate.read(cert.raw_bytes)
        end

        @leaf_certificate = certs.first
        certs.each do |cert|
          raise Error::InvalidBundle, "Root CA in chain" if cert.ca?
        end
      when :certificate
        @leaf_certificate = Internal::X509::Certificate.read(verification_material.certificate.raw_bytes)
      else
        raise Error::InvalidBundle, "Unsupported bundle content: #{content.inspect}"
      end
      raise Error::InvalidBundle, "expected certificate to be leaf" unless @leaf_certificate.leaf?
    end

    def expected_hashed_rekord_tlog_entry(hashed_input, verifier_pem)
      {
        "spec" => {
          "signature" => {
            "content" => Internal::Util.base64_encode(message_signature.signature),
            "publicKey" => {
              "content" => Internal::Util.base64_encode(verifier_pem)
            }
          },
          "data" => {
            "hash" => {
              "algorithm" => Internal::Util.hash_algorithm_name(hashed_input.algorithm),
              "value" => Internal::Util.hex_encode(hashed_input.digest)
            }
          }
        },
        "kind" => "hashedrekord",
        "apiVersion" => "0.0.1"
      }
    end

    def expected_intoto_0_0_2_tlog_entry(_verifier_pem)
      {
        "apiVersion" => "0.0.2",
        "kind" => "intoto",
        "spec" => {
          "content" => {
            "envelope" => {
              "payloadType" => dsse_envelope.payloadType,
              "payload" => Internal::Util.base64_encode(Internal::Util.base64_encode(dsse_envelope.payload)),
              "signatures" => dsse_envelope.signatures.map do |sig|
                {
                  "publicKey" =>
                    # needed because #to_pem packs the key in base64 with m*
                    Internal::Util.base64_encode(
                      "-----BEGIN CERTIFICATE-----\n" \
                      "#{Internal::Util.base64_encode(leaf_certificate.to_der)}\n" \
                      "-----END CERTIFICATE-----\n"
                    ),
                  "sig" => Internal::Util.base64_encode(Internal::Util.base64_encode(sig.sig))
                }
              end
            },
            "payloadHash" => {
              "algorithm" => "sha256",
              "value" => OpenSSL::Digest::SHA256.hexdigest(dsse_envelope.payload)
            }
          }
        }
      }
    end

    def expected_dsse_0_0_1_tlog_entry(verifier_pem)
      {
        "apiVersion" => "0.0.1",
        "kind" => "dsse",
        "spec" => {
          "payloadHash" => {
            "algorithm" => "sha256",
            "value" => OpenSSL::Digest::SHA256.hexdigest(dsse_envelope.payload)
          },
          "signatures" =>
            dsse_envelope.signatures.map do |sig|
              {
                "signature" => Internal::Util.base64_encode(sig.sig),
                "verifier" => Internal::Util.base64_encode(verifier_pem)
              }
            end
        }
      }
    end
  end
end
