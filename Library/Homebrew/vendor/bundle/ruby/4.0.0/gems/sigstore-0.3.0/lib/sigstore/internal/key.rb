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

require_relative "util"

module Sigstore
  module Internal
    class Key
      include Loggable

      def self.from_key_details(key_details, key_bytes, key_id: nil)
        case key_details
        when Common::V1::PublicKeyDetails::PKIX_ECDSA_P256_SHA_256
          key_type = "ecdsa"
          key_schema = "ecdsa-sha2-nistp256"
        when Common::V1::PublicKeyDetails::PKCS1_RSA_PKCS1V5
          key_type = "rsa"
          key_schema = "rsa-pkcs1v15-sha256"
        when Common::V1::PublicKeyDetails::PKIX_ED25519
          # Rekor v2 (tiled) logs sign checkpoints with an Ed25519 key. The raw_bytes
          # are a DER-encoded SubjectPublicKeyInfo, not the bare 32-byte key. The log id
          # is a C2SP signed-note key hash over the log's name, not a digest of the key
          # bytes, so it cannot be recomputed from the key alone; the trusted root must
          # declare it. Without it the key could never match a real entry, so refuse to
          # register an unusable key.
          unless key_id
            raise Error::MissingLogId,
                  "Ed25519 (Rekor v2) key has no declared log id; the trusted root must provide log_id.key_id"
          end

          return ED25519.new("ed25519", "ed25519", ED25519.public_key_from_spki_der(key_bytes), key_id:)
        else
          # Skip unrecognized key types instead of raising an error.
          # This allows the library to work with newer trusted roots that include
          # key types we don't yet support.
          logger.warn { "Skipping unrecognized key type: #{key_details}" }
          return nil
        end

        # The transparency log declares its own log id in the trusted root; prefer it so
        # the keyring is keyed the same way entries reference the log. For ECDSA/RSA keys
        # the log id is a plain SHA-256 of the key bytes, so it can be recomputed when the
        # trusted root omits it.
        key_id ||= OpenSSL::Digest::SHA256.hexdigest(key_bytes)

        read(key_type, key_schema, key_bytes, key_id:)
      end

      def self.read(key_type, schema, key_bytes, key_id: nil)
        case key_type
        when "ecdsa", "ecdsa-sha2-nistp256"
          pkey = OpenSSL::PKey::EC.new(key_bytes)
          EDCSA.new(key_type, schema, pkey, key_id:)
        when "ed25519"
          pkey = ED25519.pkey_from_der([key_bytes].pack("H*"))
          ED25519.new(key_type, schema, pkey, key_id:)
        when "rsa"
          pkey = OpenSSL::PKey::RSA.new(key_bytes)
          RSA.new(key_type, schema, pkey, key_id:)
        else
          raise ArgumentError, "Unsupported key type #{key_type}"
        end
      rescue OpenSSL::PKey::PKeyError => e
        raise OpenSSL::PKey::PKeyError, "Invalid key: #{e} for #{key_type} #{schema} #{key_id}"
      end

      attr_reader :key_type, :schema, :key_id

      def initialize(key_type, schema, key, key_id: nil)
        @key_type = key_type
        @key = key
        @schema = schema
        @key_id = key_id
      end

      def to_pem
        @key.to_pem
      end

      def to_der
        @key.to_der
      end

      def verify(algo, signature, data)
        @key.verify(algo, signature, data)
      rescue OpenSSL::PKey::PKeyError => e
        logger.debug { "Verification failed: #{e}" }
        false
      end

      def public_to_der
        @key.public_to_der
      end

      class EDCSA < Key
        def initialize(...)
          super
          unless @key_type == "ecdsa" || @key_type == "ecdsa-sha2-nistp256"
            raise ArgumentError,
                  "key_type must be edcsa, given #{@key_type}"
          end
          unless @key.is_a?(OpenSSL::PKey::EC)
            raise ArgumentError,
                  "key must be an OpenSSL::PKey::EC, is #{@key.inspect}"
          end

          case @schema
          when "ecdsa-sha2-nistp256"
            unless @key.group.curve_name == "prime256v1"
              raise ArgumentError, "Expected prime256v1 curve, got #{@key.group.curve_name}"
            end
          else
            raise ArgumentError, "Unsupported schema #{schema}"
          end
        end
      end

      class RSA < Key
        def initialize(...)
          super
          raise ArgumentError, "key_type must be rsa, given #{@key_type}" unless @key_type == "rsa"

          unless @key.is_a?(OpenSSL::PKey::RSA)
            raise ArgumentError, "key must be an OpenSSL::PKey::RSA, given #{@key.inspect}"
          end

          case @schema
          when "rsassa-pss-sha256"
            raise Error::UnsupportedPlatform, "RSA-PSS verification unsupported" unless @key.respond_to?(:verify_pss)
          when "rsa-pkcs1v15-sha256"
            # supported
          else
            raise ArgumentError, "Unsupported schema #{schema}"
          end
        end

        def verify(_algo, signature, data)
          case @schema
          when "rsassa-pss-sha256"
            @key.verify_pss("sha256", signature, data, salt_length: :auto, mgf1_hash: "SHA256")
          when "rsa-pkcs1v15-sha256"
            super
          else
            raise ArgumentError, "Unsupported schema #{schema}"
          end
        end
      end

      class ED25519 < Key
        # jruby-openssl cannot parse or verify Ed25519 keys, so on JRuby we hold a
        # java.security.PublicKey instead of an OpenSSL::PKey and route loading and
        # verification through the JDK (mirroring the java.security path in X509).
        JAVA_ED25519 = RUBY_ENGINE == "jruby"

        # Load an Ed25519 public key from a DER-encoded SubjectPublicKeyInfo.
        def self.public_key_from_spki_der(der)
          if JAVA_ED25519
            spec = java.security.spec.X509EncodedKeySpec.new(der.to_java_bytes)
            java.security.KeyFactory.getInstance("Ed25519").generatePublic(spec)
          else
            OpenSSL::PKey.read(der)
          end
        end

        # +raw+ is the bare 32-byte public key, not a SubjectPublicKeyInfo.
        def self.pkey_from_der(raw)
          if JAVA_ED25519
            # Wrap the raw key in the fixed Ed25519 SubjectPublicKeyInfo prefix.
            public_key_from_spki_der(["302a300506032b6570032100"].pack("H*") + raw)
          elsif OpenSSL::PKey.respond_to?(:new_raw_public_key)
            OpenSSL::PKey.new_raw_public_key("ed25519", raw)
          else
            pem = <<~PEM
              -----BEGIN PUBLIC KEY-----
              MCowBQYDK2VwAyEA#{Internal::Util.base64_encode(raw)}
              -----END PUBLIC KEY-----
            PEM
            OpenSSL::PKey.read(pem)
          end
        end

        def initialize(...)
          super
          raise ArgumentError, "key_type must be ed25519, given #{@key_type}" unless @key_type == "ed25519"

          if JAVA_ED25519
            unless @key.respond_to?(:getAlgorithm) && %w[Ed25519 EdDSA].include?(@key.getAlgorithm)
              raise ArgumentError, "key must be a java Ed25519 PublicKey, is #{@key.inspect}"
            end
          elsif !(@key.is_a?(OpenSSL::PKey::PKey) && @key.oid == "ED25519")
            raise ArgumentError, "key must be an OpenSSL::PKey::PKey with oid ED25519, is #{@key.inspect}"
          end

          raise ArgumentError, "Unsupported schema #{schema}" unless @schema == "ed25519"
        end

        def verify(_algo, signature, data)
          return java_verify(signature, data) if JAVA_ED25519

          super(nil, signature, data)
        end

        # Ed25519 keys do not implement #to_der; the SubjectPublicKeyInfo DER is the
        # public encoding.
        def to_der
          return String.from_java_bytes(@key.getEncoded).b if JAVA_ED25519

          @key.public_to_der
        end

        def public_to_der
          to_der
        end

        def to_pem
          return super unless JAVA_ED25519

          "-----BEGIN PUBLIC KEY-----\n#{Internal::Util.base64_encode(to_der)}\n-----END PUBLIC KEY-----\n"
        end

        private

        def java_verify(signature, data)
          sig = java.security.Signature.getInstance("Ed25519")
          sig.initVerify(@key)
          sig.update(data.to_java_bytes)
          sig.verify(signature.to_java_bytes)
        rescue java.security.GeneralSecurityException => e
          logger.debug { "Ed25519 verification failed: #{e}" }
          false
        end
      end
    end
  end
end
