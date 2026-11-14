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

require "openssl"
require "protobug_sigstore_protos"

require_relative "error"
require_relative "tuf"

module Sigstore
  # Parses a SigningConfig (signingconfig.v0.2) document and selects the
  # services (Fulcio CA, OIDC provider, Rekor transparency log, Timestamping
  # Authority) a client should use to sign.
  #
  # The document is decoded through the protobuf-specs SigningConfig message
  # (shipped since protobug_sigstore_protos 0.2.0). The service-selection
  # algorithm mirrors sigstore-python's SigningConfig._get_valid_services: per
  # kind, keep services whose major API version is supported and whose validity
  # window covers now, collapse to one service per operator (highest supported
  # version), then apply the ServiceConfiguration selector (ANY/EXACT/ALL).
  class SigningConfig
    MEDIA_TYPE = "application/vnd.dev.sigstore.signingconfig.v0.2+json"

    REGISTRY = Protobug::Registry.new do |registry|
      Sigstore::TrustRoot::V1.register_sigstore_trustroot_protos(registry)
    end

    Selector = Sigstore::TrustRoot::V1::ServiceSelector

    REKOR_VERSIONS = [1, 2].freeze
    TSA_VERSIONS = [1].freeze
    FULCIO_VERSIONS = [1].freeze
    OIDC_VERSIONS = [1].freeze

    # The signing config published by the public-good (or staging) Sigstore
    # instance via TUF, or nil if the repository does not publish one. Mirrors
    # TrustedRoot.production/.staging.
    def self.production(offline: false)
      from_tuf(TUF::DEFAULT_TUF_URL, offline)
    end

    def self.staging(offline: false)
      from_tuf(TUF::STAGING_TUF_URL, offline)
    end

    def self.from_tuf(url, offline)
      updater = TUF::TrustUpdater.new(url, offline)
      updater.refresh unless offline
      from_tuf_updater(updater)
    end

    # Build from an already-refreshed TrustUpdater, so a caller that also needs
    # the trusted root can share one updater (and one refresh).
    def self.from_tuf_updater(updater)
      path = updater.signing_config_path
      path && from_file(path)
    end

    def self.from_file(path)
      from_json(Gem.read_binary(path))
    end

    def self.from_json(contents)
      new(Sigstore::TrustRoot::V1::SigningConfig.decode_json(contents, registry: REGISTRY))
    rescue Protobug::Error => e
      raise Error::InvalidSigningConfig, "invalid signing config: #{e.message}"
    end

    def initialize(config)
      unless config.media_type == MEDIA_TYPE
        raise Error::InvalidSigningConfig, "unsupported signing config format: #{config.media_type.inspect}"
      end

      @fulcios = select_services(config.ca_urls, FULCIO_VERSIONS, nil)
      raise Error::InvalidSigningConfig, "No valid Fulcio CA found in signing config" if @fulcios.empty?

      @oidcs = select_services(config.oidc_urls, OIDC_VERSIONS, nil)

      @tlogs = select_services(config.rekor_tlog_urls, REKOR_VERSIONS, config.rekor_tlog_config,
                               prefer_version: preferred_rekor_major_version)
      raise Error::InvalidSigningConfig, "No valid Rekor transparency log found in signing config" if @tlogs.empty?

      @tsas = select_services(config.tsa_urls, TSA_VERSIONS, config.tsa_config)
    end

    # The Rekor transparency log to submit the signing metadata to.
    def tlog
      @tlogs.first
    end

    def fulcio
      @fulcios.first
    end

    def oidc_url
      @oidcs.first&.url
    end

    # The Timestamping Authority URLs to request RFC 3161 timestamps from.
    def tsa_urls
      @tsas.map(&:url)
    end

    private

    # On OpenSSL builds with a broken X509::Store#time (ruby/openssl#770) an RFC 3161
    # timestamp cannot be verified, and Rekor v2 entries carry no integrated time, so a
    # v2 bundle could never be verified there (even the signer's own self-verification
    # would fail). Prefer a Rekor v1 log in that case, when the signing config offers one,
    # so signing still produces a verifiable bundle.
    def preferred_rekor_major_version
      return nil unless OpenSSL::X509::Store.new.instance_variable_defined?(:@time)

      1
    end

    def select_services(services, supported_versions, config, prefer_version: nil)
      by_operator = Hash.new { |h, k| h[k] = [] }
      services.each do |service|
        next unless supported_versions.include?(service.major_api_version)
        next unless timerange_valid?(service.valid_for)

        by_operator[service.operator] << service
      end

      # One service per operator. Normally prefer the highest supported version; when
      # +prefer_version+ is supplied and an operator offers it, pick that version instead.
      result = by_operator.values.map do |op_services|
        (prefer_version && op_services.find { |s| s.major_api_version == prefer_version }) ||
          op_services.max_by(&:major_api_version)
      end

      # An absent ServiceConfiguration (or the ALL selector) imposes no count
      # constraint, so every per-operator service is returned.
      return result if config.nil? || config.selector == Selector::ALL

      if config.selector == Selector::EXACT
        count = config.count
        unless count.is_a?(Integer) && count.positive?
          raise Error::InvalidSigningConfig,
                "EXACT selector requires a positive integer count, got #{count.inspect}"
        end

        # EXACT means at least `count` services must remain after filtering and
        # per-operator collapsing; select the first `count` of them. Fewer than
        # `count` is a misconfiguration; more is acceptable (mirrors
        # sigstore-python's SigningConfig._get_valid_services).
        if result.size < count
          raise Error::InvalidSigningConfig, "Expected #{count} services in signing config, found #{result.size}"
        end

        return result.first(count)
      end

      result.first(1)
    end

    def timerange_valid?(period)
      return true unless period

      now = Time.now.utc
      return false if period.start && now < period.start.to_time
      return false if period.end && now > period.end.to_time

      true
    end
  end
end
