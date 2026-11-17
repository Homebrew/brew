# typed: strict
# frozen_string_literal: true

require "base64"
require "openssl"
require "stringio"
require "time"

module Homebrew
  module Attestation
    # Offline verifier for Homebrew's Rekor v1 DSSE bundles, including backfills.
    # OpenSSL handles signatures and certificate paths. Pinned keys and CAs must
    # cover the log's signed integrated time, including their validity window's end.
    # @api private
    module Verifier
      MINIMUM_JSON_VERSION = Gem::Version.new("2.19.2").freeze
      BUNDLE_MEDIA_TYPE = "application/vnd.dev.sigstore.bundle.v0.3+json"
      BACKFILL_MEDIA_TYPE = "application/vnd.dev.sigstore.bundle+json;version=0.2"
      PAYLOAD_TYPE = "application/vnd.in-toto+json"
      STATEMENT_TYPE = "https://in-toto.io/Statement/v1"
      LOG_ENTRY_KIND = "dsse"
      LOG_ENTRY_VERSION = "0.0.1"
      SIGNATURE_DIGEST = "SHA256"
      PAYLOAD_DIGEST = "sha256"
      LOG_HASH_ALGORITHM = "SHA2_256"
      LOG_KEY_FORMAT = "PKIX_ECDSA_P256_SHA_256"
      LOG_KEY_CURVE = "prime256v1"
      JSON_SAFE_INTEGER_MAX = T.let((1 << 53) - 1, Integer)
      SHA256_BYTES = 32
      MERKLE_LEAF_PREFIX = "\x00"
      MERKLE_NODE_PREFIX = "\x01"
      CHECKPOINT_KEY_HINT_BYTES = 4
      X509_VERSION_3 = 2
      BASIC_CONSTRAINTS_EXTENSION = "basicConstraints"
      KEY_USAGE_EXTENSION = "keyUsage"
      EXTENDED_KEY_USAGE_EXTENSION = "extendedKeyUsage"
      SUBJECT_ALTERNATIVE_NAME_EXTENSION = "subjectAltName"
      CERTIFICATE_TIMESTAMPS_EXTENSION = "ct_precert_scts"
      LEAF_BASIC_CONSTRAINTS = "CA:FALSE"
      DIGITAL_SIGNATURE_USAGE = "Digital Signature"
      CERTIFICATE_SIGNING_USAGE = "Certificate Sign"
      CODE_SIGNING_USAGE = "Code Signing"
      OIDC_ISSUER_EXTENSION = "1.3.6.1.4.1.57264.1.1"
      OIDC_ISSUER_V2_EXTENSION = "1.3.6.1.4.1.57264.1.8"
      URI_GENERAL_NAME_TAG = 6
      TIMESTAMP_VERSION = "\x00"
      CERTIFICATE_TIMESTAMP_SIGNATURE_TYPE = "\x00"
      PRECERTIFICATE_ENTRY_TYPE = "\x00\x01"
      TIMESTAMP_SIGNATURE_ALGORITHM = "\x04\x03" # TLS SHA-256 and ECDSA identifiers.
      TIMESTAMP_BYTES = 8
      LENGTH_PREFIX_BYTES = 2
      PRECERTIFICATE_LENGTH_BYTES = 3
      PRECERTIFICATE_SIZE_LIMIT = T.let(1 << 24, Integer)
      DSSE_PAE_VERSION = "DSSEv1"

      class InclusionProof < T::Struct
        const :log_index, Integer
        const :tree_size, Integer
        const :encoded_root_hash, String
        const :hashes, T::Array[String]
        const :checkpoint, String
      end

      class LogEntry < T::Struct
        const :log_index, Integer
        const :log_id, String
        const :integrated_time, Integer
        const :inclusion_promise, String
        const :inclusion_proof, InclusionProof
        const :body, String
      end

      class Bundle < T::Struct
        const :log_entry, LogEntry
        const :certificate_der, String
        const :payload, String
        const :signature, String
      end

      class ValidityPeriod < T::Struct
        const :start_time, Time
        const :end_time, T.nilable(Time)

        sig { params(time: Time).returns(T::Boolean) }
        def covers?(time)
          expiry = end_time
          time >= start_time && (!expiry || time <= expiry)
        end
      end

      class LogKey < T::Struct
        const :log_id, String
        const :public_key_der, String
        const :validity_period, ValidityPeriod
      end

      class CertificateAuthority < T::Struct
        const :certificates, T::Array[String]
        const :validity_period, ValidityPeriod
      end

      class TrustedRoot < T::Struct
        const :transparency_logs, T::Array[LogKey]
        const :certificate_transparency_logs, T::Array[LogKey]
        const :certificate_authorities, T::Array[CertificateAuthority]
      end

      class Result < T::Struct
        # Provenance fields are opaque JSON preserved for the caller.
        const :statement, T::Hash[String, T.anything]
        const :integrated_time, Time
      end

      sig { params(bundle: String, digest: String, signing_workflow: String).returns(Result) }
      def self.verify(bundle, digest, signing_workflow)
        verification_bundle = parse_bundle(bundle)
        log_entry = verification_bundle.log_entry
        integrated_time = Time.at(log_entry.integrated_time).utc
        log_public_key = trusted_key(trusted_root.transparency_logs, log_entry.log_id, integrated_time)
        verify_promise(log_entry, log_public_key)
        verify_inclusion(log_entry.body, log_entry.inclusion_proof)
        verify_checkpoint(log_entry.inclusion_proof, log_entry.log_id, log_public_key)
        leaf_certificate = OpenSSL::X509::Certificate.new(verification_bundle.certificate_der)
        certificate_chain = verify_certificate(leaf_certificate, integrated_time)
        verify_sct(leaf_certificate, certificate_chain.fetch(1), integrated_time)
        verify_identity(leaf_certificate, signing_workflow)
        verify_dsse(leaf_certificate, verification_bundle.payload, verification_bundle.signature)
        verify_body(log_entry.body, verification_bundle.payload, verification_bundle.signature, leaf_certificate)
        Result.new(statement: verify_statement(verification_bundle.payload, digest), integrated_time:)
      end

      sig { params(json: String, symbolize_names: T::Boolean).returns(T.anything) }
      def self.parse_json(json, symbolize_names: false)
        # Require patched duplicate-key error handling before parsing (CVE-2026-33210).
        # TODO: Remove this check and MINIMUM_JSON_VERSION once Homebrew pins portable Ruby with JSON >= 2.19.2.
        check(Gem::Version.new(JSON::VERSION) >= MINIMUM_JSON_VERSION, "requires JSON >= #{MINIMUM_JSON_VERSION}")
        JSON.parse(json, allow_duplicate_key: false, symbolize_names:)
      end

      sig { params(bundle: String).returns(Bundle) }
      def self.parse_bundle(bundle)
        # This exact form is the input specification, not a permissive format probe.
        parse_json(bundle, symbolize_names: true) => {
          mediaType:            BUNDLE_MEDIA_TYPE | BACKFILL_MEDIA_TYPE,
          verificationMaterial: {
            tlogEntries:               [{
              logIndex:          String => log_index,
              logId:             { keyId: String => log_id, **nil },
              kindVersion:       { kind: LOG_ENTRY_KIND, version: LOG_ENTRY_VERSION, **nil },
              integratedTime:    String => integrated_time,
              inclusionPromise:  { signedEntryTimestamp: String => inclusion_promise, **nil },
              inclusionProof:    {
                logIndex: String => proof_index, rootHash: String => root_hash, treeSize: String => tree_size,
                hashes: Array => proof_hashes, checkpoint: { envelope: String => checkpoint, **nil }, **nil
              },
              canonicalizedBody: String => body,
              **nil
            }],
            timestampVerificationData: {},
            **certificate
          },
          dsseEnvelope:         {
            payload: String => payload, payloadType: PAYLOAD_TYPE,
            signatures: [{ sig: String => signature, **nil }], **nil
          },
          **nil
        }
        certificate => { certificate: { rawBytes: String, **nil }, **nil } |
                       { x509CertificateChain: { certificates: [{ rawBytes: String, **nil }], **nil }, **nil }
        raw_certificate = certificate.dig(:certificate, :rawBytes) ||
                          certificate.fetch(:x509CertificateChain).fetch(:certificates).fetch(0).fetch(:rawBytes)
        Bundle.new(
          log_entry:       LogEntry.new(
            log_index: log_integer(log_index), log_id: Base64.strict_decode64(log_id),
            integrated_time: log_integer(integrated_time),
            inclusion_promise: Base64.strict_decode64(inclusion_promise),
            body: Base64.strict_decode64(body), inclusion_proof: InclusionProof.new(
              log_index: log_integer(proof_index), tree_size: log_integer(tree_size),
              encoded_root_hash: root_hash, checkpoint: checkpoint, hashes: proof_hashes.map do |encoded_hash|
                encoded_hash => String
                Base64.strict_decode64(encoded_hash)
              end
            )
          ),
          certificate_der: Base64.strict_decode64(raw_certificate),
          payload:         Base64.strict_decode64(payload),
          signature:       Base64.strict_decode64(signature),
        )
      end

      sig { returns(TrustedRoot) }
      def self.trusted_root
        @trusted_root ||= T.let(
          parse_trusted_root((HOMEBREW_LIBRARY_PATH/"attestation/trusted_root.json").read), T.nilable(TrustedRoot)
        )
      end

      sig { params(json: String).returns(TrustedRoot) }
      def self.parse_trusted_root(json)
        parse_json(json, symbolize_names: true) => {
          tlogs: Array => transparency_logs, ctlogs: Array => certificate_logs,
          certificateAuthorities: Array => authorities
        }
        TrustedRoot.new(
          transparency_logs:             parse_log_keys(transparency_logs),
          certificate_transparency_logs: parse_log_keys(certificate_logs),
          certificate_authorities:       authorities.map do |authority|
            authority => { validFor: Hash => validity, certChain: { certificates: Array => certificates } }
            CertificateAuthority.new(
              validity_period: parse_validity_period(validity),
              certificates:    certificates.map do |certificate|
                certificate => { rawBytes: String => raw_certificate }
                Base64.strict_decode64(raw_certificate)
              end,
            )
          end,
        )
      end

      sig { params(entries: T::Array[T.anything]).returns(T::Array[LogKey]) }
      def self.parse_log_keys(entries)
        entries.filter_map do |entry|
          next unless entry in { logId: { keyId: String => log_id }, hashAlgorithm: LOG_HASH_ALGORITHM,
                                 publicKey: { rawBytes: String => public_key, keyDetails: LOG_KEY_FORMAT,
                                              validFor: Hash => validity } }

          LogKey.new(log_id: Base64.strict_decode64(log_id), public_key_der: Base64.strict_decode64(public_key),
                     validity_period: parse_validity_period(validity))
        end
      end

      sig { params(value: T.anything).returns(ValidityPeriod) }
      def self.parse_validity_period(value)
        value => { start: String => start_time, **remaining }
        end_time = case expiry = remaining[:end]
        when String then Time.iso8601(expiry)
        when nil then nil
        else raise InvalidAttestationError, "invalid trust validity period"
        end
        ValidityPeriod.new(start_time: Time.iso8601(start_time), end_time:)
      end

      sig { params(condition: T::Boolean, message: String).void }
      def self.check(condition, message)
        raise InvalidAttestationError, "attestation verification failed: #{message}" unless condition
      end

      sig { params(value: String).returns(Integer) }
      def self.log_integer(value)
        check(value.match?(/\A(?:0|[1-9][0-9]*)\z/), "invalid log integer")
        number = Integer(value, 10)
        check(number <= JSON_SAFE_INTEGER_MAX, "log integer out of range")
        number
      end

      sig { params(log_keys: T::Array[LogKey], log_id: String, integrated_time: Time).returns(OpenSSL::PKey::EC) }
      def self.trusted_key(log_keys, log_id, integrated_time)
        log_keys.each do |log_key|
          next if log_key.log_id != log_id || !log_key.validity_period.covers?(integrated_time)

          public_key = OpenSSL::PKey::EC.new(log_key.public_key_der)
          check(public_key.group.curve_name == LOG_KEY_CURVE, "unsupported log key curve")
          return public_key
        end
        raise InvalidAttestationError, "attestation verification failed: no trusted log key at signing time"
      end

      sig { params(log_entry: LogEntry, public_key: OpenSSL::PKey::EC).void }
      def self.verify_promise(log_entry, public_key)
        # Sorted ASCII keys and integer values are the complete canonical JSON domain here.
        promise = JSON.generate(body: Base64.strict_encode64(log_entry.body),
                                integratedTime: log_entry.integrated_time,
                                logID: log_entry.log_id.unpack1("H*"), logIndex: log_entry.log_index)
        check(log_entry.integrated_time.positive? && log_entry.log_index >= 0, "invalid log time or index")
        check(public_key.verify(SIGNATURE_DIGEST, log_entry.inclusion_promise, promise), "invalid inclusion promise")
      end

      sig { params(body: String, proof: InclusionProof).void }
      def self.verify_inclusion(body, proof)
        # RFC 6962: prefix leaves with 0 and nodes with 1. This index is shard-local,
        # so it need not equal the global index in the signed inclusion promise.
        leaf_index = proof.log_index
        last_leaf_index = proof.tree_size - 1
        check(leaf_index.between?(0, last_leaf_index), "invalid inclusion proof index")
        root_hash = OpenSSL::Digest.digest(SIGNATURE_DIGEST, "#{MERKLE_LEAF_PREFIX}#{body}")
        proof.hashes.each do |sibling_hash|
          check(last_leaf_index.positive? && sibling_hash.bytesize == SHA256_BYTES, "invalid inclusion proof length")
          if leaf_index.odd? || leaf_index == last_leaf_index
            root_hash = OpenSSL::Digest.digest(SIGNATURE_DIGEST, "#{MERKLE_NODE_PREFIX}#{sibling_hash}#{root_hash}")
            while leaf_index.positive? && leaf_index.even?
              leaf_index >>= 1
              last_leaf_index >>= 1
            end
          else
            root_hash = OpenSSL::Digest.digest(SIGNATURE_DIGEST, "#{MERKLE_NODE_PREFIX}#{root_hash}#{sibling_hash}")
          end
          leaf_index >>= 1
          last_leaf_index >>= 1
        end
        check(last_leaf_index.zero? && root_hash == Base64.strict_decode64(proof.encoded_root_hash),
              "invalid inclusion proof root")
      end

      sig { params(proof: InclusionProof, log_id: String, public_key: OpenSSL::PKey::EC).void }
      def self.verify_checkpoint(proof, log_id, public_key)
        note, signatures = proof.checkpoint.split("\n\n", 2)
        raise InvalidAttestationError, "invalid checkpoint note" if !note || !signatures

        origin, checkpoint_size, checkpoint_root, *extra_lines = note.split("\n")
        check(!origin.to_s.empty? && extra_lines.empty? && checkpoint_size == proof.tree_size.to_s &&
              checkpoint_root == proof.encoded_root_hash, "checkpoint does not match inclusion proof")
        check(signatures.end_with?("\n"), "invalid checkpoint signatures")
        verified = signatures.lines.map do |line|
          signature_match = %r{\A\u2014 \S+ ([A-Za-z0-9+/=]+)\n\z}.match(line)
          raise InvalidAttestationError, "invalid checkpoint signature line" unless signature_match

          signature = Base64.strict_decode64(signature_match[1].to_s)
          signature.start_with?(log_id.byteslice(0, CHECKPOINT_KEY_HINT_BYTES).to_s) &&
            public_key.verify(SIGNATURE_DIGEST, signature.byteslice(CHECKPOINT_KEY_HINT_BYTES..).to_s, "#{note}\n")
        end
        check(verified.any?, "invalid checkpoint signature")
      end

      sig { params(leaf_certificate: OpenSSL::X509::Certificate, integrated_time: Time).returns(T::Array[OpenSSL::X509::Certificate]) }
      def self.verify_certificate(leaf_certificate, integrated_time)
        constraints = leaf_certificate.extensions.find { |extension| extension.oid == BASIC_CONSTRAINTS_EXTENSION }
        key_usage = leaf_certificate.extensions.find do |extension|
          extension.oid == KEY_USAGE_EXTENSION
        end&.value.to_s.split(", ")
        check(leaf_certificate.version == X509_VERSION_3 &&
              (!constraints || (constraints.critical? && constraints.value == LEAF_BASIC_CONSTRAINTS &&
              key_usage.none?(CERTIFICATE_SIGNING_USAGE))), "expected a leaf certificate")
        check(key_usage.include?(DIGITAL_SIGNATURE_USAGE), "missing digital signature key usage")
        check(leaf_certificate.extensions.any? do |extension|
          extension.oid == EXTENDED_KEY_USAGE_EXTENSION && extension.value.split(", ").include?(CODE_SIGNING_USAGE)
        end, "missing code signing extended key usage")
        certificate_store = OpenSSL::X509::Store.new
        intermediates = T.let([], T::Array[OpenSSL::X509::Certificate])
        trusted_root.certificate_authorities.each do |authority|
          next unless authority.validity_period.covers?(integrated_time)

          certificate_chain = authority.certificates.map { |certificate| OpenSSL::X509::Certificate.new(certificate) }
          certificate_store.add_cert(certificate_chain.fetch(-1))
          intermediates.concat(certificate_chain.first(certificate_chain.length - 1))
        end
        verification_context = OpenSSL::X509::StoreContext.new(certificate_store, leaf_certificate, intermediates)
        verification_context.time = integrated_time
        check(verification_context.verify, "invalid Fulcio certificate chain or signing time")
        verification_context.chain || raise(InvalidAttestationError, "missing verified certificate chain")
      end

      sig { params(leaf_certificate: OpenSSL::X509::Certificate, issuer_certificate: OpenSSL::X509::Certificate, integrated_time: Time).void }
      def self.verify_sct(leaf_certificate, issuer_certificate, integrated_time)
        extension = leaf_certificate.extensions.find { |candidate| candidate.oid == CERTIFICATE_TIMESTAMPS_EXTENSION }
        raise InvalidAttestationError, "missing SCT" unless extension

        OpenSSL::ASN1.decode(extension.value_der) => OpenSSL::ASN1::OctetString => timestamp_octets
        timestamp_octets.value => String => timestamp_bytes
        timestamp_list = StringIO.new(timestamp_bytes)
        timestamp_list_length = read_bytes(timestamp_list, LENGTH_PREFIX_BYTES).unpack1("n")
        check(timestamp_list_length == timestamp_bytes.bytesize - LENGTH_PREFIX_BYTES,
              "invalid SCT list length")
        precertificate = leaf_certificate.dup
        # RFC 6962 precertificate signatures cover the TBS without the SCT extension.
        precertificate.extensions = leaf_certificate.extensions.reject do |candidate|
          candidate.oid == CERTIFICATE_TIMESTAMPS_EXTENSION
        end
        # Force re-encoding: to_der can retain the SCT in OpenSSL's cached body.
        certificate_body = precertificate.tbs_bytes
        check(certificate_body.bytesize < PRECERTIFICATE_SIZE_LIMIT, "SCT certificate too large")
        timestamp_count = 0
        until timestamp_list.eof?
          certificate_timestamp = StringIO.new(read_length_prefixed(timestamp_list))
          check(read_bytes(certificate_timestamp, TIMESTAMP_VERSION.bytesize) == TIMESTAMP_VERSION,
                "unsupported SCT version")
          log_id = read_bytes(certificate_timestamp, SHA256_BYTES)
          timestamp = read_bytes(certificate_timestamp, TIMESTAMP_BYTES)
          extensions = read_length_prefixed(certificate_timestamp)
          signature_algorithm = read_bytes(certificate_timestamp, TIMESTAMP_SIGNATURE_ALGORITHM.bytesize)
          check(signature_algorithm == TIMESTAMP_SIGNATURE_ALGORITHM, "unsupported SCT signature algorithm")
          signature = read_length_prefixed(certificate_timestamp)
          check(certificate_timestamp.eof?, "trailing SCT bytes")
          certificate_length = [certificate_body.bytesize].pack("N").byteslice(-PRECERTIFICATE_LENGTH_BYTES,
                                                                               PRECERTIFICATE_LENGTH_BYTES)
          issuer_key_hash = OpenSSL::Digest.digest(SIGNATURE_DIGEST, issuer_certificate.public_key.public_to_der)
          signed_timestamp = "#{TIMESTAMP_VERSION}#{CERTIFICATE_TIMESTAMP_SIGNATURE_TYPE}" \
                             "#{timestamp}#{PRECERTIFICATE_ENTRY_TYPE}#{issuer_key_hash}" \
                             "#{certificate_length}#{certificate_body}#{[extensions.bytesize].pack("n")}#{extensions}"
          check(trusted_key(trusted_root.certificate_transparency_logs, log_id, integrated_time)
                .verify(SIGNATURE_DIGEST, signature, signed_timestamp), "invalid SCT signature")
          timestamp_count += 1
        end
        check(timestamp_count.positive?, "missing SCT")
      end

      sig { params(stream: StringIO, length: Integer).returns(String) }
      def self.read_bytes(stream, length)
        bytes = stream.read(length)
        raise InvalidAttestationError, "truncated SCT" if !bytes || bytes.bytesize != length

        bytes
      end

      sig { params(stream: StringIO).returns(String) }
      def self.read_length_prefixed(stream)
        read_bytes(stream, read_bytes(stream, LENGTH_PREFIX_BYTES).unpack1("n"))
      end

      sig { params(leaf_certificate: OpenSSL::X509::Certificate, workflow: String).void }
      def self.verify_identity(leaf_certificate, workflow)
        issuers = leaf_certificate.extensions.filter_map do |extension|
          case extension.oid
          when OIDC_ISSUER_EXTENSION then extension.value_der
          when OIDC_ISSUER_V2_EXTENSION
            issuer_name = OpenSSL::ASN1.decode(extension.value_der)
            issuer_name.value if issuer_name.is_a?(OpenSSL::ASN1::UTF8String)
          end
        end
        check(issuers.any?(GITHUB_ACTIONS_ISSUER), "OIDC issuer does not match")
        alternative_names = leaf_certificate.extensions.find do |extension|
          extension.oid == SUBJECT_ALTERNATIVE_NAME_EXTENSION
        end
        raise InvalidAttestationError, "missing SAN" unless alternative_names

        names = OpenSSL::ASN1.decode(alternative_names.value_der)
        check(names.is_a?(OpenSSL::ASN1::Sequence) && names.value.any? do |name|
          name.tag_class == :CONTEXT_SPECIFIC && name.tag == URI_GENERAL_NAME_TAG && name.value == workflow
        end, "SANs do not match")
      end

      sig { params(leaf_certificate: OpenSSL::X509::Certificate, payload: String, signature: String).void }
      def self.verify_dsse(leaf_certificate, payload, signature)
        pre_authentication_encoding = "#{DSSE_PAE_VERSION} #{PAYLOAD_TYPE.bytesize} #{PAYLOAD_TYPE} " \
                                      "#{payload.bytesize} #{payload}"
        check(leaf_certificate.public_key.verify(SIGNATURE_DIGEST, signature, pre_authentication_encoding),
              "invalid DSSE signature")
      end

      sig { params(body: String, payload: String, signature: String, leaf_certificate: OpenSSL::X509::Certificate).void }
      def self.verify_body(body, payload, signature, leaf_certificate)
        parse_json(body, symbolize_names: true) => Hash => logged_entry
        logged_entry.fetch(:spec).delete(:envelopeHash) # Hash of unavailable, uncanonicalised upload bytes.
        logged_entry => {
          apiVersion: LOG_ENTRY_VERSION, kind: LOG_ENTRY_KIND,
          spec: {
            payloadHash: { algorithm: PAYLOAD_DIGEST, value: String => payload_hash, **nil },
            signatures: [{ signature: String => logged_signature, verifier: String => logged_certificate, **nil }],
            **nil
          }, **nil
        }
        check(payload_hash == OpenSSL::Digest::SHA256.hexdigest(payload) &&
              logged_signature == Base64.strict_encode64(signature) &&
              logged_certificate == Base64.strict_encode64(leaf_certificate.to_pem),
              "log body does not match envelope")
      end

      sig { params(payload: String, digest: String).returns(T::Hash[String, T.anything]) }
      def self.verify_statement(payload, digest)
        check(digest.match?(/\A[0-9a-f]{#{SHA256_BYTES * 2}}\z/i), "expected a SHA-256 digest")
        parse_json(payload) => Hash => statement
        statement.fetch("_type") => String => statement_type
        check(statement_type == STATEMENT_TYPE, "expected in-toto v1 statement")
        statement.fetch("subject") => Array => subjects
        matches = subjects.map do |subject|
          subject => Hash => subject_fields
          subject_fields.fetch("digest") => Hash => subject_digests
          check(!subject_digests.empty?, "missing subject digest")
          subject_digests[PAYLOAD_DIGEST] == digest.downcase
        end
        check(matches.any?, "None of in-toto subjects matches artifact")
        statement
      end
    end
  end
end
