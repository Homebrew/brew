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

require "delegate"
require "openssl"

require "protobug_sigstore_protos"

require_relative "tuf"

module Sigstore
  REGISTRY = Protobug::Registry.new do |registry|
    Sigstore::TrustRoot::V1.register_sigstore_trustroot_protos(registry)
    Sigstore::Bundle::V1.register_sigstore_bundle_protos(registry)
  end
  class TrustedRoot < DelegateClass(Sigstore::TrustRoot::V1::TrustedRoot)
    def self.production(offline: false)
      from_tuf(TUF::DEFAULT_TUF_URL, offline)
    end

    def self.staging(offline: false)
      from_tuf(TUF::STAGING_TUF_URL, offline)
    end

    def self.from_tuf(url, offline)
      from_tuf_updater(TUF::TrustUpdater.new(url, offline).tap { _1.refresh unless offline })
    end

    # Build from an already-refreshed TrustUpdater, so a caller that also needs
    # the signing config can share one updater (and one refresh).
    def self.from_tuf_updater(updater)
      from_file(updater.trusted_root_path)
    end

    def self.from_file(path)
      contents = Gem.read_binary(path)
      new Sigstore::TrustRoot::V1::TrustedRoot.decode_json(contents, registry: REGISTRY)
    end

    def rekor_keys
      # A trusted root may list more than one transparency log (e.g. a Rekor v1
      # instance alongside a Rekor v2 tiled log). The keyring selects the right
      # key per entry by log id, so return all of them.
      keys = tlog_keys(tlogs).to_a
      raise Error::InvalidBundle, "Did not find any Rekor keys" if keys.empty?

      keys
    end

    def ctfe_keys
      keys = tlog_keys(ctlogs).to_a
      raise Error::InvalidBundle, "Did not find any CTFE keys" if keys.empty?

      keys
    end

    def fulcio_cert_chains
      chains = ca_keys(certificate_authorities, allow_expired: true).map do |certs|
        certs.map { |raw_bytes| Internal::X509::Certificate.read(raw_bytes) }
      end
      raise Error::InvalidBundle, "Fulcio certificates not found in trusted root" if chains.none?(&:any?)

      chains
    end

    def tlog_for_signing
      tlogs.find do |ctlog|
        timerange_valid?(ctlog.public_key.valid_for, allow_expired: false)
      end
    end

    def certificate_authority_for_signing
      certificate_authorities.find do |ca|
        timerange_valid?(ca.valid_for, allow_expired: false)
      end
    end

    private

    def tlog_keys(tlogs)
      return enum_for(__method__, tlogs) unless block_given?

      tlogs.each do |transparency_log_instance|
        key = transparency_log_instance.public_key
        # Verification keyring: include keys whose validity window has started, allowing
        # already-expired keys so historical entries still verify, but skipping keys that
        # are not yet valid. This mirrors the signing-path window check in #tlog_for_signing
        # and sigstore-python's verify-purpose keyring (allow_expired: true).
        next unless timerange_valid?(key.valid_for, allow_expired: true)

        declared_log_id = transparency_log_instance.log_id&.key_id
        key_id = declared_log_id.unpack1("H*") if declared_log_id && !declared_log_id.empty?
        parsed_key = Internal::Key.from_key_details(key.key_details, key.raw_bytes, key_id:)
        yield parsed_key if parsed_key
      end
    end

    def ca_keys(certificate_authorities, allow_expired:)
      return enum_for(__method__, certificate_authorities, allow_expired:) unless block_given?

      certificate_authorities.each do |ca|
        next unless timerange_valid?(ca.valid_for, allow_expired:)

        yield ca.cert_chain.certificates.map(&:raw_bytes)
      end
    end

    def timerange_valid?(period, allow_expired:)
      now = Time.now.utc
      return true unless period
      return false if now < period.start.to_time
      return true if allow_expired
      return false if period.end && now > period.end.to_time

      true
    end
  end
end
