# typed: strict
# frozen_string_literal: true

# A `DelegateClass`, whose constructor and delegated methods tapioca does not see.
class Sigstore::TrustedRoot
  sig { params(trusted_root: Sigstore::TrustRoot::V1::TrustedRoot).void }
  def initialize(trusted_root); end

  sig { returns(T::Array[Sigstore::TrustRoot::V1::CertificateAuthority]) }
  def timestamp_authorities; end
end
