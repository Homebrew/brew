# typed: strict
# frozen_string_literal: true

require "cacheable"

module Homebrew
  module API
    # Helper functions for using the analytics JSON API.
    #
    # Analytics files are unsigned, so only analytics data is retained from
    # them: per-package responses are reduced to their `analytics` key before
    # anything else can observe or cache them.
    module Analytics
      extend T::Generic
      extend Cacheable

      Cache = type_template { { fixed: T::Hash[String, T.untyped] } }

      private_class_method :cache

      class << self
        sig { returns(String) }
        def analytics_api_path
          "analytics"
        end

        sig { params(category: String, days: T.any(Integer, String)).returns(T::Hash[String, T.untyped]) }
        def fetch(category, days)
          endpoint = "#{analytics_api_path}/#{category}/#{days}d.json"
          cache[endpoint] ||= fetch_json(endpoint)
        end

        sig { params(name: String).returns(T.nilable(T::Hash[String, T.untyped])) }
        def formula_analytics(name)
          package_analytics "formula/#{name}.json"
        end

        sig { params(token: String).returns(T.nilable(T::Hash[String, T.untyped])) }
        def cask_analytics(token)
          package_analytics "cask/#{token}.json"
        end

        private

        # The cached response is revalidated hourly so repeated `brew info`
        # runs do not download it again.
        sig { params(endpoint: String).returns(T.nilable(T::Hash[String, T.untyped])) }
        def package_analytics(endpoint)
          return cache[endpoint] if cache.key?(endpoint)

          json, = Homebrew::API.fetch_json_api_file(endpoint, stale_seconds: Homebrew::API::UNSIGNED_API_STALE_SECONDS)
          analytics = json["analytics"] if json.is_a?(Hash)
          cache[endpoint] = (analytics if analytics.is_a?(Hash))
        end

        sig { params(endpoint: String).returns(T::Hash[String, T.untyped]) }
        def fetch_json(endpoint)
          api_url = "#{Homebrew::EnvConfig.api_domain}/#{endpoint}"
          output = Utils::Curl.curl_output("--fail", api_url)
          if !output.success? && Homebrew::EnvConfig.api_domain != HOMEBREW_API_DEFAULT_DOMAIN
            # Fall back to the default API domain and try again
            api_url = "#{HOMEBREW_API_DEFAULT_DOMAIN}/#{endpoint}"
            output = Utils::Curl.curl_output("--fail", api_url)
          end
          raise ArgumentError, "No file found at: #{Tty.underline}#{api_url}#{Tty.reset}" unless output.success?

          json = begin
            JSON.parse(output.stdout, freeze: true)
          rescue JSON::ParserError
            nil
          end
          raise ArgumentError, "Invalid JSON file: #{Tty.underline}#{api_url}#{Tty.reset}" unless json.is_a?(Hash)

          json
        end
      end
    end
  end
end
