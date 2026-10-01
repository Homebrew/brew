# typed: strict
# frozen_string_literal: true

require "livecheck/strategic"

module Homebrew
  module Livecheck
    module Strategy
      # The {HeaderMatch} strategy follows all URL redirections and scans
      # the resulting headers for matching text using the provided regex.
      #
      # This strategy is not applied automatically and it's necessary to use
      # `strategy :header_match` in a `livecheck` block to apply it.
      class HeaderMatch
        extend Strategic

        # A priority of zero causes livecheck to skip the strategy. We do this
        # for {HeaderMatch} so we can selectively apply it when appropriate.
        PRIORITY = 0

        # The `Regexp` used to determine if the strategy applies to the URL.
        URL_MATCH_REGEX = %r{^https?://}i

        # The header fields to check when a `strategy` block isn't provided.
        DEFAULT_HEADERS_TO_CHECK = ["content-disposition", "location"].freeze

        # Whether the strategy can be applied to the provided URL.
        #
        # @param url [String] the URL to match against
        # @return [Boolean]
        sig { override.params(url: String).returns(T::Boolean) }
        def self.match?(url)
          URL_MATCH_REGEX.match?(url)
        end

        # Identify versions from HTTP headers.
        #
        # @param headers [Array<Hash<String, String>>] an array of response HTTP
        #   header hashes to check for versions
        # @param regex [Regexp, nil] a regex for matching versions in content
        # @return [Array]
        sig {
          params(
            headers: T::Array[T::Hash[String, T.any(String, T::Array[String])]],
            regex:   T.nilable(Regexp),
            block:   T.nilable(Proc),
          ).returns(T::Array[String])
        }
        def self.versions_from_content(headers, regex = nil, &block)
          # Merge the last value of each header from all responses into one hash
          # for convenience
          merged_headers = T.cast(headers.reduce(&:merge), T::Hash[String, T.any(String, T::Array[String])])

          if block
            block_return_value = case block.parameters[0]
            when [:opt, :headers], [:req, :headers], [:rest], [:req]
              regex.present? ? yield(merged_headers, regex) : yield(merged_headers)
            when [:opt, :all_headers], [:req, :all_headers]
              regex.present? ? yield(headers, regex) : yield(headers)
            else
              raise ArgumentError,
                    "First argument of #{Utils.demodulize(name)} `strategy` block must be `headers` or `all_headers`"
            end
            return Strategy.handle_block_return(block_return_value)
          end

          DEFAULT_HEADERS_TO_CHECK.filter_map do |header_name|
            header_value = merged_headers[header_name]
            header_value = header_value.last if header_value.is_a?(Array)
            next if header_value.blank?

            if regex
              header_value[regex, 1]
            else
              v = Version.parse(header_value, detected_from_url: true)
              v.null? ? nil : v.to_s
            end
          end.uniq
        end

        # Checks the final URL for new versions after following all redirections,
        # using the provided regex for matching.
        #
        # @param url [String] the URL to fetch
        # @param regex [Regexp, nil] a regex for matching versions
        # @param content [String, nil] content to check instead of fetching
        # @param options [Options] options to modify behavior
        # @return [Hash]
        sig {
          override.params(
            url:     String,
            regex:   T.nilable(Regexp),
            content: T.nilable(String),
            options: Options,
            block:   T.nilable(Proc),
          ).returns(T::Hash[Symbol, T.anything])
        }
        def self.find_versions(url:, regex: nil, content: nil, options: Options.new, &block)
          match_data = { matches: {}, regex:, url: }
          match_data[:cached] = true if content
          return match_data if url.blank?

          content = if content
            Json.parse_json(content)
          else
            match_data[:content] = Strategy.page_headers(url, options:)
          end
          return match_data if content.blank?

          versions_from_content(content, regex, &block).each do |version_text|
            match_data[:matches][version_text] = Version.new(version_text)
          end

          require "json"
          match_data[:content] = JSON.generate(match_data[:content]) unless match_data[:cached]
          match_data
        end
      end
    end
  end
end
