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

require_relative "trusted_root"
require_relative "policy"
require_relative "internal/keyring"
require_relative "internal/merkle"
require_relative "internal/set"
require_relative "rekor/client"
require_relative "rekor/checkpoint"
require_relative "internal/x509"

module Sigstore
  class Verifier
    include Loggable

    attr_reader :rekor_client

    def initialize(rekor_client:, fulcio_cert_chains:, timestamp_authorities:, rekor_keyring:, ct_keyring:)
      @rekor_client = rekor_client
      @fulcio_cert_chains = fulcio_cert_chains
      @timestamp_authorities = timestamp_authorities
      @rekor_keyring = rekor_keyring
      @ct_keyring = ct_keyring
    end

    def self.for_trust_root(trust_root:)
      new(
        rekor_client: Rekor::Client.new(url: trust_root.tlog_for_signing.base_url),
        fulcio_cert_chains: trust_root.fulcio_cert_chains,
        timestamp_authorities: trust_root.timestamp_authorities,
        rekor_keyring: Internal::Keyring.new(keys: trust_root.rekor_keys),
        ct_keyring: Internal::Keyring.new(keys: trust_root.ctfe_keys)
      )
    end

    def self.production(trust_root: TrustedRoot.production)
      for_trust_root(trust_root:)
    end

    def self.staging(trust_root: TrustedRoot.staging)
      for_trust_root(trust_root:)
    end

    # +key+ is an out-of-band public key (an OpenSSL::PKey) used to verify "managed"
    # (bring-your-own-key) bundles, which carry a public key hint instead of a Fulcio
    # certificate. It must be supplied for, and only for, such bundles.
    def verify(input:, policy:, offline:, key: nil)
      # First, establish a time for the signature. This timestamp is required to validate the certificate chain,
      # so this step comes first.

      bundle = input.sbundle
      materials = bundle.verification_material

      if bundle.key_based?
        unless key
          return VerificationFailure.new("bundle is signed with a managed key but no verifying key was provided")
        end
      elsif key
        return VerificationFailure.new("a verifying key was provided but the bundle contains a signing certificate")
      end

      # 1)
      # If the verification policy uses the Timestamping Service, the Verifier MUST verify the timestamping response
      # using the Timestamping Service root key material, as described in Spec: Timestamping Service, with the raw bytes
      # of the signature as the timestamped data. The Verifier MUST then extract a timestamp from the timestamping
      # response. If verification or timestamp parsing fails, the Verifier MUST abort.

      # Only resolve the data the timestamp binds to (and enforce its constraints) when
      # there is a timestamp to verify; absent timestamp data there is nothing to bind.
      timestamp_data = materials.timestamp_verification_data
      timestamps = extract_timestamp_from_verification_data(
        timestamp_data, timestamp_data && timestamped_data(bundle)
      ) || []

      # 2)
      # If the verification policy uses timestamps from the Transparency Service, the Verifier MUST verify the signature
      # on the Transparency Service LogEntry as described in Spec: Transparency Service against the pre-distributed root
      # key material from the transparency service. The Verifier SHOULD NOT (yet) attempt to parse the body.
      # The Verifier MUST then parse the integratedTime as a Unix timestamp (seconds since January 1, 1970 UTC).
      # If verification or timestamp parsing fails, the Verifier MUST abort.

      begin
        # TODO: should this instead be an input to the verify method?
        # See https://docs.google.com/document/d/1kbhK2qyPPk8SLavHzYSDM8-Ueul9_oxIMVFuWMWKz0E/edit?disco=AAABQVV-gT0
        entry = find_rekor_entry(bundle, input.hashed_input, offline:, signing_key: key)
      rescue Sigstore::Error::MissingRekorEntry
        return VerificationFailure.new("Rekor entry not found")
      else
        if entry.inclusion_proof&.checkpoint
          Internal::Merkle.verify_merkle_inclusion(entry)
          Rekor::Checkpoint.verify_checkpoint(@rekor_keyring, entry)
        elsif !offline
          return VerificationFailure.new("Missing Rekor inclusion proof")
        else
          logger.warn "inclusion proof not present in bundle: skipping due to offline verification"
        end
      end

      Internal::SET.verify_set(keyring: @rekor_keyring, entry:) if entry.inclusion_promise

      # Rekor v1 entries carry an integrated time signed by the log; Rekor v2 (tiled)
      # entries do not, and rely on a Timestamping Service response for the signing time.
      integrated_time = entry.integrated_time
      timestamps << Time.at(integrated_time).utc if integrated_time&.positive?

      if timestamps.empty?
        return VerificationFailure.new(
          "no trusted signing time available (no timestamp authority response and no log integrated time)"
        )
      end

      # 3)
      # The Verifier MUST perform certification path validation (RFC 5280 §6) of the certificate chain with the
      # pre-distributed Fulcio root certificate(s) as a trust anchor, but with a fake “current time.”
      # If a timestamp from the timestamping service is available, the Verifier MUST perform path validation using the
      # timestamp from the Timestamping Service. If a timestamp from the Transparency Service is available, the Verifier
      # MUST perform path validation using the timestamp from the Transparency Service. If both are available, the
      # Verifier performs path validation twice. If either fails, verification fails.
      #
      # Steps 3-5 are certificate-specific: a managed-key bundle has no certificate to do
      # path validation, SCT verification, or identity-policy checks against, so they are
      # skipped. The signature (and its binding to the Rekor entry) is still verified below
      # against the supplied key.

      if bundle.key_based? && !policy.is_a?(Policy::UnsafeNoOp)
        logger.warn do
          "ignoring identity policy #{policy.class} for managed-key bundle: managed-key " \
            "verification trusts the supplied key, not a certificate identity"
        end
      end

      unless bundle.key_based?
        chains = timestamps.map do |ts|
          chain, err = Internal::X509.validate_chain(@fulcio_cert_chains, bundle.leaf_certificate, ts)
          return err if err

          chain
        end

        chains.uniq! { |chain| chain.map(&:to_der) }
        unless chains.size == 1
          raise "expected exactly one certificate chain, got #{chains.size} chains:\n" +
                chains.map do |chain|
                  chain.map(&:to_text).join("\n")
                end.join("\n\n")
        end

        # 4)
        # Unless performing online verification (see §Alternative Workflows), the Verifier MUST extract the
        # SignedCertificateTimestamp embedded in the leaf certificate, and verify it as in RFC 9162 §8.1.3,
        # using the verification key from the Certificate Transparency Log.
        chain = chains.first
        if (result = verify_scts(bundle.leaf_certificate, chain)) && !result.verified?
          return result
        end

        # 5)
        # The Verifier MUST then check the certificate against the verification policy.

        usage_ext = bundle.leaf_certificate.extension(Internal::X509::Extension::KeyUsage)
        unless usage_ext.digital_signature
          return VerificationFailure.new("Key usage is not of type `digital signature`")
        end

        extended_key_usage = bundle.leaf_certificate.extension(Internal::X509::Extension::ExtendedKeyUsage)
        unless extended_key_usage.code_signing?
          return VerificationFailure.new("Extended key usage is not of type `code signing`")
        end

        policy_check = policy.verify(bundle.leaf_certificate)
        return policy_check unless policy_check.verified?
      end

      # 6)
      # By this point, the Verifier has already verified the signature by the Transparency Service (§Establishing a Time
      #  for the Signature). The Verifier MUST parse body: body is a base64-encoded JSON document with keys apiVersion
      #  and kind. The Verifier implementation contains a list of known Transparency Service formats (by apiVersion and
      #  kind); if no type is found, abort. The Verifier MUST parse body as the given type.
      #
      # Then, the Verifier MUST check the following; exactly how to do this will be specified by each type in Spec:
      # Sigstore Registries (§Signature Metadata Formats):
      #
      #  * The signature from the parsed body is the same as the provided signature.
      #  * The key or certificate from the parsed body is the same as in the input certificate.
      #  * The “subject” of the parsed body matches the artifact.

      signing_key = bundle.key_based? ? key : bundle.leaf_certificate.public_key

      case bundle.content
      when :message_signature
        # The messageDigest is an unauthenticated hint, but when present it must be
        # consistent with the artifact being verified.
        message_digest = bundle.message_signature.message_digest
        if message_digest && !message_digest.digest.empty? && message_digest.digest != input.hashed_input.digest
          return VerificationFailure.new("message digest does not match the artifact")
        end

        verified = verify_raw(signing_key, bundle.message_signature.signature, input.hashed_input.digest)
        return VerificationFailure.new("Signature verification failed") unless verified
      when :dsse_envelope
        verify_dsse(bundle.dsse_envelope, signing_key) or
          return VerificationFailure.new("DSSE envelope verification failed")

        case bundle.dsse_envelope.payloadType
        when "application/vnd.in-toto+json"
          in_toto = begin
            JSON.parse(bundle.dsse_envelope.payload)
          rescue JSON::ParserError
            raise Error::InvalidBundle, "invalid JSON for in-toto statement in DSSE payload"
          end
          if (result = verify_in_toto(input, in_toto))
            return result
          end
        else
          raise Sigstore::Error::Unimplemented,
                "unsupported DSSE payload type: #{bundle.dsse_envelope.payloadType.inspect}"
        end
      else
        raise Error::InvalidBundle, "unknown content type: #{bundle.content}"
      end

      VerificationSuccess.new
    end

    private

    def verify_raw(public_key, signature, data)
      if public_key.respond_to?(:verify_raw)
        public_key.verify_raw(nil, signature, data)
      else
        case public_key
        when OpenSSL::PKey::EC
          public_key.dsa_verify_asn1(data, signature)
        else
          raise Error::Unimplemented, "unsupported public key type: #{public_key.class} for raw verification"
        end
      end
    end

    def verify_dsse(dsse_envelope, public_key)
      signatures = dsse_envelope.signatures

      pae = dsse_pae(dsse_envelope)

      raise Error::InvalidBundle, "DSSEv1 envelope missing signatures" if signatures.empty?

      signatures.all? do |signature|
        public_key.verify("SHA256", signature.sig, pae)
      end
    end

    def dsse_pae(dsse_envelope)
      Internal::Util.dsse_pae(dsse_envelope.payloadType, dsse_envelope.payload)
    end

    def verify_in_toto(input, in_toto_payload)
      type = in_toto_payload["_type"]
      raise Error::InvalidBundle, "Expected in-toto statement, got #{type.inspect}" unless type == "https://in-toto.io/Statement/v1"

      subjects = in_toto_payload["subject"]
      raise Error::InvalidBundle, "Expected in-toto statement with subject" if !subjects || subjects.empty?

      expected_algorithm = Internal::Util.hash_algorithm_name(input.hashed_input.algorithm)
      expected_hexdigest = Internal::Util.hex_encode(input.hashed_input.digest)

      matched = subjects.map do |subject|
        digest = subject["digest"]
        raise Error::InvalidBundle, "Expected in-toto statement with digest" if !digest || digest.empty?

        digest[expected_algorithm] == expected_hexdigest
      end.any?

      return if matched

      VerificationFailure.new(
        "None of in-toto subjects matches artifact for #{expected_algorithm}: #{expected_hexdigest}"
      )
    end

    public

    def verify_scts(leaf_certificate, chain)
      sct_list = leaf_certificate
                 .extension(Internal::X509::Extension::PrecertificateSignedCertificateTimestamps)
                 .signed_certificate_timestamps
      raise Error::InvalidCertificate, "no SCTs found" if sct_list.empty?

      sct_list.each do |sct|
        verified = verify_sct(
          sct,
          leaf_certificate,
          chain,
          @ct_keyring
        )
        return VerificationFailure.new("SCT verification failed") unless verified
      end

      nil
    end

    private

    def verify_sct(sct, certificate, chain, ct_keyring)
      if sct.entry_type == 1
        issuer_cert = find_issuer_cert(chain)
        issuer_pubkey = issuer_cert.public_key
        unless issuer_cert.ca?
          raise Error::InvalidCertificate, "Invalid issuer pubkey basicConstraint (not a CA): #{issuer_cert.to_pem}"
        end

        # TODO: use public_to_der when available
        issuer_key_id = OpenSSL::Digest::SHA256.digest(issuer_pubkey.to_der)
      end

      digitally_signed = pack_digitally_signed(sct, certificate, issuer_key_id).b

      ct_keyring.verify(key_id: sct.log_id, signature: sct.signature, data: digitally_signed)
    end

    def pack_digitally_signed(sct, certificate, issuer_key_id = nil)
      # https://datatracker.ietf.org/doc/html/rfc6962#section-3.4
      # https://datatracker.ietf.org/doc/html/rfc6962#section-3.5
      #
      #   digitally-signed struct {
      #     Version sct_version;
      #     SignatureType signature_type = certificate_timestamp;
      #     uint64 timestamp;
      #     LogEntryType entry_type;
      #     select(entry_type) {
      #         case x509_entry: ASN.1Cert;
      #         case precert_entry: PreCert;
      #     } signed_entry;
      #    CtExtensions extensions;
      # };

      signed_entry =
        case sct.entry_type
        when 0 # x509_entry
          cert_der = certificate.to_public_der
          cert_len = cert_der.bytesize
          unused, len1, len2, len3 = [cert_len].pack("N").unpack("C4")
          raise Error::InvalidCertificate, "invalid cert_len #{cert_len} #{cert_der.inspect}" if unused != 0

          [len1, len2, len3, cert_der].pack("CCC a#{cert_len}")
        when 1 # precert_entry
          unless issuer_key_id&.bytesize == 32
            raise Error::InvalidCertificate,
                  "issuer_key_id must be 32 bytes for precert, given #{issuer_key_id.inspect}"
          end

          tbs_cert = certificate.tbs_certificate_der
          tbs_cert_len = tbs_cert.bytesize
          unused, len1, len2, len3 = [tbs_cert_len].pack("N").unpack("C4")
          raise Error::InvalidCertificate, "invalid tbs_cert_len #{tbs_cert_len} #{tbs_cert.inspect}" if unused != 0

          [issuer_key_id, len1, len2, len3, tbs_cert].pack("a32 CCC a#{tbs_cert_len}")
        else
          raise Error::Unimplemented, "only x509_entry and precert_entry supported, given #{sct.entry_type.inspect}"
        end

      [
        sct.version,
        0,
        sct.timestamp,
        sct.entry_type,
        signed_entry,
        sct.extensions_bytes&.bytesize.to_i,
        sct.extensions_bytes
      ].pack(<<~PACK)
        C # version
        C # signature_type
        Q> # timestamp
        n # entry_type
        a#{signed_entry.bytesize} # signed_entry
        n # extensions length
        a#{sct.extensions_bytes&.bytesize.to_i} # extension
      PACK
    end

    def find_issuer_cert(chain)
      issuer = chain[0]
      issuer = chain[1] if issuer.preissuer?
      raise Error::InvalidCertificate, "no issuer certificate found" unless issuer

      issuer
    end

    # The raw bytes a Timestamping Service response is expected to be computed over: the
    # signature in the bundle (RFC 3161 message imprint covers these bytes).
    def timestamped_data(bundle)
      case bundle.content
      when :message_signature
        bundle.message_signature.signature
      when :dsse_envelope
        # The timestamp binds to a single signature; with more than one envelope
        # signature it is ambiguous which one the imprint covers, so refuse to bind
        # only the first (mirrors the v2 consistency path, which requires exactly one).
        signatures = bundle.dsse_envelope.signatures
        raise Error::InvalidBundle, "expected exactly one DSSE signature to bind a timestamp to" if signatures.size > 1

        signatures.first&.sig
      end
    end

    def extract_timestamp_from_verification_data(data, signed_data)
      # TODO: allow requiring a verified timestamp
      unless data
        logger.debug { "no timestamp verification data" }
        return nil
      end

      # Checks for https://github.com/ruby/openssl/pull/770
      if OpenSSL::X509::Store.new.instance_variable_defined?(:@time)
        logger.warn do
          "OpenSSL::X509::Store on this version of openssl (#{OpenSSL::VERSION}) does not set time properly, " \
            "this breaks TSA verification"
        end
        return
      end

      # The timestamp MUST be computed over the bundle signature (the RFC 3161 message
      # imprint covers it). Without signature bytes to bind it to we cannot perform that
      # binding, so fail closed rather than accept a timestamp over arbitrary data.
      if signed_data.nil? || signed_data.empty?
        raise Error::InvalidTimestamp, "no signature available to bind the timestamp to"
      end

      authorities = @timestamp_authorities.map do |ta|
        store = OpenSSL::X509::Store.new
        chain = ta.cert_chain.certificates.map do |cert|
          Internal::X509::Certificate.read(cert.raw_bytes).openssl
        end
        chain.each do |cert|
          store.add_cert(cert)
        end
        [ta, chain, store]
      end

      # https://www.rfc-editor.org/rfc/rfc3161.html#section-2.4.2
      data.rfc3161_timestamps.map do |ts|
        resp = OpenSSL::Timestamp::Response.new(ts.signed_timestamp)

        req = OpenSSL::Timestamp::Request.new
        req.cert_requested = !(resp.token.certificates.nil? || resp.token.certificates.empty?)
        req.message_imprint = resp.token_info.message_imprint
        req.algorithm = resp.token_info.algorithm
        req.policy_id = resp.token_info.policy_id if resp.token_info.policy_id
        req.nonce = resp.token_info.nonce if resp.token_info.nonce
        req.version = resp.token_info.version

        # The message imprint must cover the bundle's signature; otherwise the timestamp
        # attests to unrelated data and must be rejected.
        expected_imprint =
          begin
            OpenSSL::Digest.new(resp.token_info.algorithm).digest(signed_data)
          rescue StandardError => e
            raise Error::InvalidTimestamp,
                  "unsupported timestamp digest algorithm #{resp.token_info.algorithm.inspect}: #{e}"
          end
        unless resp.token_info.message_imprint == expected_imprint
          raise Error::InvalidTimestamp, "timestamp message imprint does not match the bundle signature"
        end

        verified = authorities.any? do |ta, chain, store|
          # The timestamp must fall within the window the trusted root says this
          # Timestamping Service was valid for, independent of cert-chain validity.
          gen_time = resp.token_info.gen_time
          valid_for = ta.valid_for
          if valid_for
            next false if valid_for.start && gen_time < valid_for.start.to_time
            next false if valid_for.end && gen_time > valid_for.end.to_time
          end

          store.time = gen_time

          resp.verify(req, store, chain) &&
            (logger.debug do
               "timestamp (#{resp.to_text}) verified for #{ta}"
             end || true)
        rescue OpenSSL::Timestamp::TimestampError => e
          logger.error { "timestamp verification failed (#{e})" }
          false
        end
        raise Error::InvalidTimestamp, "timestamp verification failed" unless verified

        resp.token_info.gen_time
      end
    end

    def find_rekor_entry(bundle, hashed_input, offline:, signing_key: nil)
      raise Error::InvalidBundle, "multiple tlog entries" if bundle.verification_material.tlog_entries.size > 1

      rekor_entry = bundle.verification_material.tlog_entries&.first
      has_inclusion_promise = !rekor_entry.nil? && !rekor_entry.inclusion_promise.nil?
      has_inclusion_proof = !rekor_entry.nil? && !rekor_entry.inclusion_proof&.checkpoint.nil?

      logger.debug do
        "Looking for rekor entry, " \
          "has_inclusion_promise=#{has_inclusion_promise} has_inclusion_proof=#{has_inclusion_proof}"
      end

      # Rekor v2 (tiled) entries always ship an inclusion proof in the bundle and have no
      # online retrieval API; detect them from the embedded entry and verify consistency
      # against the bundle directly, rather than reconstructing a v1 canonicalized body.
      if rekor_entry && (v2_body = rekor_v2_body(rekor_entry))
        # A v2 entry has no integrated time and no online retrieval API, so the only
        # binding to the log is the Merkle inclusion proof and its checkpoint signature.
        # Require them here so the v2 path can never reach the offline warn-and-skip
        # branch in #verify (even though #validate_version! also enforces this for
        # non-0.1 bundles): without a checkpoint there is nothing to verify against.
        unless rekor_entry.inclusion_proof&.checkpoint
          raise Error::InvalidBundle, "Rekor v2 entry must contain an inclusion proof with a checkpoint"
        end

        verify_rekor_v2_entry_consistency(bundle, hashed_input, v2_body, signing_key:)
        return rekor_entry
      end

      verifier_pem = signing_key&.public_to_pem || bundle.leaf_certificate&.to_pem
      expected_entry = bundle.expected_tlog_entry(hashed_input, verifier_pem)

      entry = if offline
                logger.debug { "Offline verification, skipping rekor" }
                rekor_entry
              elsif !has_inclusion_proof
                logger.debug { "No inclusion proof, searching rekor" }
                @rekor_client.log.entries.retrieve.post(expected_entry)
              else
                logger.debug { "Using rekor entry in sigstore bundle" }
                rekor_entry
              end

      raise Error::MissingRekorEntry, "Rekor entry not found" unless entry

      logger.debug { "Found rekor entry: #{entry}" }

      actual_body = parse_canonicalized_body(entry)
      if bundle.dsse_envelope?
        # since the hash is over the uncanonicalized envelope, we need to remove it
        #
        # NOTE(sigstore-python): This is very slightly weaker than the consistency check
        # for hashedrekord entries, due to how inclusion is recorded for DSSE:
        # the included entry for DSSE includes an envelope hash that we
        # *cannot* verify, since the envelope is uncanonicalized JSON.
        # Instead, we manually pick apart the entry body below and verify
        # the parts we can (namely the payload hash and signature list).
        case actual_body["kind"]
        when "intoto"
          actual_body["spec"]["content"].delete("hash")
        when "dsse"
          actual_body["spec"].delete("envelopeHash")
        else
          raise Error::InvalidRekorEntry, "Unknown kind: #{actual_body["kind"]}"
        end
      end

      if actual_body != expected_entry
        require "pp"
        raise Error::InvalidRekorEntry, "Invalid rekor entry:\n\n" \
                                        "Envelope:\n#{bundle.dsse_envelope.pretty_inspect}\n\n" \
                                        "Diff:\n#{diff_json(expected_entry, actual_body).pretty_inspect}"
      end

      entry
    end

    # Parsed canonicalized body if this is a Rekor v2 (hashedrekord 0.0.2) entry, else nil.
    # A body that is not JSON returns nil so the v1 reconstruction path handles it.
    def rekor_v2_body(entry)
      body = parse_canonicalized_body(entry)
      body if body.values_at("kind", "apiVersion") == ["hashedrekord", "0.0.2"]
    rescue Error::InvalidRekorEntry
      nil
    end

    def parse_canonicalized_body(entry)
      JSON.parse(entry.canonicalized_body)
    rescue JSON::ParserError
      raise Error::InvalidRekorEntry, "invalid JSON in rekor entry canonicalized_body"
    end

    # Verify that a Rekor v2 hashedrekord (0.0.2) entry corresponds to the artifact,
    # signature, and signing certificate in the bundle. The Merkle inclusion proof and
    # checkpoint signature bind this body to the log; #find_rekor_entry has already
    # confirmed both are present, and #verify performs that verification. Here we bind
    # the body to the inputs we are verifying.
    def verify_rekor_v2_entry_consistency(bundle, hashed_input, body, signing_key: nil)
      spec = body.dig("spec", "hashedRekordV002")
      raise Error::InvalidRekorEntry, "missing hashedRekordV002 spec" unless spec

      logged_algorithm = spec.dig("data", "algorithm")
      logged_digest = decode_base64_field(spec.dig("data", "digest"), "data.digest")
      logged_signature = decode_base64_field(spec.dig("signature", "content"), "signature.content")

      if bundle.key_based?
        logged_key = decode_base64_field(
          spec.dig("signature", "verifier", "publicKey", "rawBytes"),
          "signature.verifier.publicKey.rawBytes"
        )
        unless logged_key == signing_key.public_to_der
          raise Error::InvalidRekorEntry, "rekor entry public key does not match the supplied key"
        end
      else
        logged_cert = decode_base64_field(
          spec.dig("signature", "verifier", "x509Certificate", "rawBytes"),
          "signature.verifier.x509Certificate.rawBytes"
        )
        unless logged_cert == bundle.leaf_certificate.to_der
          raise Error::InvalidRekorEntry, "rekor entry certificate does not match the bundle certificate"
        end
      end

      expected_algorithm, expected_digest, expected_signature =
        rekor_v2_expected_data_and_signature(bundle, hashed_input)

      unless logged_algorithm == expected_algorithm
        raise Error::InvalidRekorEntry,
              "rekor entry data algorithm #{logged_algorithm.inspect} does not match " \
              "expected #{expected_algorithm.inspect}"
      end
      unless logged_digest == expected_digest
        raise Error::InvalidRekorEntry, "rekor entry data digest does not match the artifact"
      end
      return if logged_signature == expected_signature

      raise Error::InvalidRekorEntry, "rekor entry signature does not match the bundle signature"
    end

    # The expected [data.algorithm, data.digest, signature] for the bundle, named to match
    # the Rekor v2 `hashedRekordV002` spec fields (algorithm uses the proto enum name).
    def rekor_v2_expected_data_and_signature(bundle, hashed_input)
      case bundle.content
      when :message_signature
        [hashed_input.algorithm.name, hashed_input.digest, bundle.message_signature.signature]
      when :dsse_envelope
        # "hashedrekord-over-DSSE": the logged data is SHA2-256 of PAE(payloadType, payload)
        # and the logged signature is the (single) DSSE envelope signature.
        signatures = bundle.dsse_envelope.signatures
        unless signatures.size == 1
          raise Error::InvalidRekorEntry, "expected exactly one DSSE signature for a Rekor v2 entry"
        end

        ["SHA2_256", OpenSSL::Digest::SHA256.digest(dsse_pae(bundle.dsse_envelope)), signatures.first.sig]
      else
        raise Error::InvalidBundle, "expected either message_signature or dsse_envelope"
      end
    end

    def decode_base64_field(value, name)
      raise Error::InvalidRekorEntry, "missing #{name} in rekor entry" unless value

      Internal::Util.base64_decode(value)
    rescue ArgumentError
      raise Error::InvalidRekorEntry, "invalid base64 in #{name} of rekor entry"
    end

    def diff_json(a, b) # rubocop:disable Naming/MethodParameterName
      return nil if a == b

      return [a, b] if a.class != b.class

      case a
      when Hash
        (a.keys | b.keys).to_h do |k|
          [k, diff_json(a[k], b[k])]
        end.compact
      when Array
        a.zip(b).filter_map { |x, y| diff_json(x, y) }
      when String
        begin
          da = a.unpack1("m0")
          db = b.unpack1("m0")

          [{ "decoded" => da, "base64" => a },
           { "decoded" => db, "base64" => b }]
        rescue ArgumentError
          [a, b]
        end
      else
        [a, b]
      end
    end
  end
end
