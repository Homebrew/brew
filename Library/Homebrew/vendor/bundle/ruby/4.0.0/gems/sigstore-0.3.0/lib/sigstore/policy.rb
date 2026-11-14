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
  module Policy
    class SingleX509ExtPolicy
      def initialize(value)
        @value = value
      end

      def verify(cert)
        ext = cert.openssl.find_extension(oid)
        unless ext
          return VerificationFailure.new("Certificate does not contain #{self.class.name&.[](/::([^:]+)$/, 1)} " \
                                         "(#{oid}) extension")
        end

        value = ext_value(ext)
        verified = value == @value
        unless verified
          return VerificationFailure.new("Certificate's #{self.class.name&.[](/::([^:]+)$/, 1)} does not match " \
                                         "(got #{value}, expected #{@value})")
        end

        VerificationSuccess.new
      end

      if RUBY_ENGINE == "jruby"
        def ext_value(ext)
          der = ext.to_der
          seq = OpenSSL::ASN1.decode(der)
          seq.value.last.value
        end
      else
        def ext_value(ext)
          ext.value
        end
      end

      def oid
        self.class::OID # : String
      end
    end

    class OIDCIssuer < SingleX509ExtPolicy
      OID = "1.3.6.1.4.1.57264.1.1"
    end

    class SingleX509ExtDerEncodedPolicy < SingleX509ExtPolicy
      def ext_value(ext)
        OpenSSL::ASN1.decode(ext.value_der).value
      end
    end

    class OIDCIssuerV2 < SingleX509ExtDerEncodedPolicy
      OID = "1.3.6.1.4.1.57264.1.8"
    end

    class AnyOf
      def initialize(*policies)
        @policies = policies
      end

      def verify(cert)
        failures = []
        @policies.each do |policy|
          result = policy.verify(cert)
          return result if result.verified?

          failures << result.reason
        end

        VerificationFailure.new("No policy matched: #{failures.join(", ")}")
      end
    end

    # No identity to check: used for managed-key (bring-your-own-key) verification,
    # where trust comes from the supplied key rather than a certificate identity.
    class UnsafeNoOp
      def verify(_cert)
        VerificationSuccess.new
      end
    end

    class Identity
      def initialize(identity:, issuer:)
        @identity = identity
        @issuer = AnyOf.new(OIDCIssuer.new(issuer), OIDCIssuerV2.new(issuer))
      end

      def verify(cert)
        issuer_verified = @issuer.verify(cert)
        return issuer_verified unless issuer_verified.verified?

        san_ext = cert.extension(Sigstore::Internal::X509::Extension::SubjectAlternativeName)
        raise Error::InvalidCertificate, "Certificate does not contain subjectAltName extension" unless san_ext

        verified = san_ext.general_names.any? { |_, id| id == @identity }
        unless verified
          return VerificationFailure.new(
            "Certificate's SANs do not match #{@identity}; actual SANs: #{san_ext.general_names}"
          )
        end

        VerificationSuccess.new
      end
    end
  end
end
