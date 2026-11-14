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

require "net/http"
require_relative "../version"

module Sigstore
  module Rekor
    class Client
      DEFAULT_REKOR_URL = "https://rekor.sigstore.dev"
      STAGING_REKOR_URL = "https://rekor.sigstage.dev"

      def initialize(url:)
        @url = URI.join(url, "api/v1/")

        net = defined?(Gem::Net) ? Gem::Net : Net
        @session = net::HTTP.new(@url.host, @url.port)
        @session.use_ssl = true
      end

      def self.production
        new(url: DEFAULT_REKOR_URL)
      end

      def self.staging
        new(url: STAGING_REKOR_URL)
      end

      def log
        Log.new(URI.join(@url, "log/"), session: @session)
      end
    end

    # Client for the Rekor v2 (tiled / rekor-tiles) API. Unlike v1, creating an
    # entry returns a fully-formed protobuf TransparencyLogEntry (including the
    # inclusion proof and checkpoint) directly, so there is no separate retrieval
    # step. See https://github.com/sigstore/rekor-tiles/blob/main/CLIENTS.md
    class V2Client
      def initialize(url:)
        @url = URI.join("#{url.chomp("/")}/", "api/v2/")

        net = defined?(Gem::Net) ? Gem::Net : Net
        @session = net::HTTP.new(@url.host, @url.port)
        @session.use_ssl = true
      end

      # Submit a proposed entry (a CreateEntryRequest, as a Hash) and return the
      # integrated V1::TransparencyLogEntry. The log only responds once the entry
      # has been included, so this call can take a while.
      def create_entry(payload)
        resp = @session.post2(URI.join(@url, "log/entries").path, payload.to_json,
                              { "Content-Type" => "application/json", "Accept" => "application/json",
                                "User-Agent" => Sigstore::USER_AGENT })

        unless %w[200 201].include?(resp.code)
          raise Error::FailedRekorPost,
                "#{resp.code} #{resp.message.inspect}\n#{JSON.pretty_generate(payload)}\n#{resp.body}"
        end
        unless resp.content_type == "application/json"
          raise Error::FailedRekorPost, "Unexpected content type: #{resp.content_type.inspect}"
        end

        V1::TransparencyLogEntry.decode_json(resp.body, registry: REGISTRY)
      end
    end

    class Log
      def initialize(url, session:)
        @url = url
        @session = session
      end

      def entries
        Entries.new(URI.join(@url, "entries/"), session: @session)
      end
    end

    class Entries
      def initialize(url, session:)
        @url = url
        @session = session
      end

      def retrieve
        Retrieve.new(URI.join(@url, "retrieve/"), session: @session)
      end

      def post(entry)
        resp = @session.post2(@url.path.chomp("/"), entry.to_json,
                              { "Content-Type" => "application/json", "Accept" => "application/json",
                                "User-Agent" => Sigstore::USER_AGENT })

        unless resp.code == "201"
          raise Error::FailedRekorPost,
                "#{resp.code} #{resp.message.inspect}\n#{JSON.pretty_generate(entry)}\n#{resp.body}"
        end
        unless resp.content_type == "application/json"
          raise Error::FailedRekorPost, "Unexpected content type: #{resp.content_type.inspect}"
        end

        body = JSON.parse(resp.body)
        Entries.decode_transparency_log_entry(body)
      end

      class Retrieve
        def initialize(url, session:)
          @url = url
          @session = session
        end

        def post(expected_entry)
          data = { entries: [expected_entry] }
          resp = @session.post2(@url.path, data.to_json,
                                { "Content-Type" => "application/json", "Accept" => "application/json",
                                  "User-Agent" => Sigstore::USER_AGENT })

          if resp.code != "200"
            raise Error::FailedRekorLookup,
                  "#{resp.code} #{resp.message.inspect}\n#{JSON.pretty_generate(data)}\n#{resp.body}"
          end

          results = JSON.parse(resp.body)

          results.map do |result|
            Entries.decode_transparency_log_entry(result)
          end.min_by(&:integrated_time)
        end
      end

      def self.decode_transparency_log_entry(response)
        raise ArgumentError, "response must be a Hash" unless response.is_a?(Hash)
        raise ArgumentError, "Received multiple entries in response" if response.size != 1

        _, result = response.first
        canonicalized_body = Internal::Util.base64_decode(result.fetch("body"))
        body = JSON.parse(canonicalized_body)
        entry = V1::TransparencyLogEntry.new
        entry.log_index = result.fetch("logIndex")
        entry.log_id = Common::V1::LogId.new
        entry.log_id.key_id = Internal::Util.hex_decode(result.fetch("logID"))
        entry.kind_version = V1::KindVersion.new
        entry.kind_version.kind = body.fetch("kind")
        entry.kind_version.version = body.fetch("apiVersion")
        entry.integrated_time = result.fetch("integratedTime")
        entry.canonicalized_body = canonicalized_body
        if (set = result.dig("verification", "signedEntryTimestamp"))
          entry.inclusion_promise = V1::InclusionPromise.new
          entry.inclusion_promise.signed_entry_timestamp = Internal::Util.base64_decode(set)
        end
        if (inclusion_proof = result.dig("verification", "inclusionProof"))
          entry.inclusion_proof = V1::InclusionProof.new
          entry.inclusion_proof.checkpoint = V1::Checkpoint.new
          entry.inclusion_proof.checkpoint.envelope = inclusion_proof.fetch("checkpoint")
          entry.inclusion_proof.hashes = inclusion_proof.fetch("hashes").map { |h| Internal::Util.hex_decode(h) }
          entry.inclusion_proof.log_index = inclusion_proof.fetch("logIndex")
          entry.inclusion_proof.root_hash = Internal::Util.hex_decode(inclusion_proof.fetch("rootHash"))
          entry.inclusion_proof.tree_size = inclusion_proof.fetch("treeSize")
        end

        entry
      end
    end
  end
end
