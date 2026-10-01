# typed: strict
# frozen_string_literal: true

require "json"
require "utils/curl"

module Homebrew
  module Vulns
    # Client for https://google.github.io/osv.dev/api/.
    module OSV
      API_BASE = "https://api.osv.dev/v1"
      BATCH_SIZE = 1000
      MAX_PAGES = 100

      class Error < RuntimeError; end
      class ApiError < Error; end
      class NotFoundError < ApiError; end

      Package = T.type_alias { { ecosystem: String, name: String, version: T.nilable(String) } }

      # POST /v1/querybatch. Returns one array of vuln hashes per input package,
      # in the same order. Follows per-result `next_page_token` continuations.
      # A `nil` version queries all known vulnerabilities for the package.
      sig { params(packages: T::Array[Package]).returns(T::Array[T::Array[T::Hash[String, T.untyped]]]) }
      def self.query_batch(packages)
        return [] if packages.empty?

        results = Array.new(packages.size) { [] }

        packages.each_slice(BATCH_SIZE).with_index do |batch, batch_index|
          offset = batch_index * BATCH_SIZE
          pending = batch.map.with_index do |pkg, index|
            query = T.let({ package: { name: pkg.fetch(:name), ecosystem: pkg.fetch(:ecosystem) } },
                          T::Hash[Symbol, T.untyped])
            query[:version] = pkg.fetch(:version) if pkg.fetch(:version)
            { slot: offset + index, query: }
          end

          page = 0
          while pending.any?
            page += 1
            if page > MAX_PAGES
              raise ApiError, "OSV API returned more than #{MAX_PAGES} pages for a querybatch; aborting"
            end

            response = post("#{API_BASE}/querybatch", { queries: pending.map { |p| p.fetch(:query) } })
            batch_results = response["results"]
            if !batch_results.is_a?(Array) || batch_results.length != pending.length
              got = batch_results.is_a?(Array) ? batch_results.length : batch_results.class
              raise ApiError,
                    "OSV API querybatch: expected #{pending.length} results, got #{got}"
            end

            continued = []
            batch_results.each_with_index do |result, index|
              entry = pending.fetch(index)
              results.fetch(entry.fetch(:slot)).concat(Array(result["vulns"]))
              token = result["next_page_token"]
              next if token.to_s.empty?

              continued << {
                slot:  entry.fetch(:slot),
                query: entry.fetch(:query).merge(page_token: token),
              }
            end
            pending = continued
          end
        end

        results
      end

      # GET /v1/vulns/{id}.
      sig { params(id: String).returns(T::Hash[String, T.untyped]) }
      def self.vulnerability(id)
        get("#{API_BASE}/vulns/#{ERB::Util.url_encode(id)}")
      end

      sig { params(url: String, payload: T::Hash[T.untyped, T.untyped]).returns(T::Hash[String, T.untyped]) }
      private_class_method def self.post(url, payload)
        request(url, "--json", JSON.generate(payload), "--request", "POST")
      end

      sig { params(url: String).returns(T::Hash[String, T.untyped]) }
      private_class_method def self.get(url)
        request(url)
      end

      sig { params(url: String, extra_args: String).returns(T::Hash[String, T.untyped]) }
      private_class_method def self.request(url, *extra_args)
        # curl_args supplies Homebrew's retry count and curl's transient-error
        # backoff. Bound each transfer and the retry window for long sweeps.
        # This placeholder is interpreted by curl, not Ruby.
        # rubocop:disable Style/FormatStringToken
        result = Utils::Curl.curl_output("--fail", "--location", "--silent", "--write-out", "\n%{http_code}",
                                         *extra_args, url, connect_timeout: 15, max_time: 60, retry_max_time: 120)
        # rubocop:enable Style/FormatStringToken
        body, _, status = result.stdout.rpartition("\n")
        unless result.success?
          raise(
            if result.exit_status == 22 && status == "404" && url.start_with?("#{API_BASE}/vulns/")
              NotFoundError
            else
              ApiError
            end,
            "OSV API request to #{url} failed (curl exit #{result.exit_status}): #{result.stderr}",
          )
        end

        JSON.parse(body)
      rescue JSON::ParserError => e
        raise ApiError, "Invalid JSON from OSV API at #{url}: #{e.message}"
      end
    end
  end
end
