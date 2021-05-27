# typed: true
# frozen_string_literal: true

module Homebrew
  module Livecheck
    module Strategy
      # The {PageMatch} strategy fetches content at a URL and scans it for
      # matching text using the provided regex.
      #
      # This strategy can be used in a `livecheck` block when no specific
      # strategies apply to a given URL. Though {PageMatch} will technically
      # match any HTTP URL, the strategy also requires a regex to function.
      #
      # The {find_versions} method is also used within other
      # strategies, to handle the process of identifying version text in
      # content.
      #
      # @api public
      class PageMatch
        extend T::Sig

        NICE_NAME = "Page match"

        # A priority of zero causes livecheck to skip the strategy. We do this
        # for PageMatch so we can selectively apply the strategy only when a
        # regex is provided in a `livecheck` block.
        PRIORITY = 0

        # The `Regexp` used to determine if the strategy applies to the URL.
        URL_MATCH_REGEX = %r{^https?://}i.freeze

        # Whether the strategy can be applied to the provided URL.
        # PageMatch will technically match any HTTP URL but is only
        # usable with a `livecheck` block containing a regex.
        sig { params(url: String).returns(T::Boolean) }
        def self.match?(url)
          URL_MATCH_REGEX.match?(url)
        end

        # Uses the regex to match text in the content or, if a block is
        # provided, passes the page content to the block to handle matching.
        # With either approach, an array of unique matches is returned.
        #
        # @param content [String] the page content to check
        # @param regex [Regexp] a regex used for matching versions in the
        #   content
        # @return [Array]
        def self.page_matches(content, regex, &block)
          if block
            case (value = block.call(content, regex))
            when String
              return [value]
            when Array
              return value
            else
              raise TypeError, "Return value of `strategy :page_match` block must be a string or array of strings."
            end
          end

          content.scan(regex).map do |match|
            case match
            when String
              match
            else
              match.first
            end
          end.uniq
        end

        # Checks the content at the URL for new versions, using the provided
        # regex for matching.
        #
        # @param url [String] the URL of the content to check
        # @param regex [Regexp] a regex used for matching versions in content
        # @param provided_content [String] page content to use in place of
        #   fetching via Strategy#page_content
        # @return [Hash]
        sig {
          params(
            url:              String,
            regex:            T.nilable(Regexp),
            cask:             T.nilable(Cask::Cask),
            provided_content: T.nilable(String),
            block:            T.nilable(T.proc.params(arg0: String).returns(T.any(T::Array[String], String))),
          ).returns(T::Hash[Symbol, T.untyped])
        }
        def self.find_versions(url, regex, cask: nil, provided_content: nil, &block)
          match_data = { matches: {}, regex: regex, url: url }

          content = if provided_content.is_a?(String)
            match_data[:cached] = true
            provided_content
          else
            match_data.merge!(Strategy.page_content(url))
            match_data[:content]
          end
          return match_data if content.blank?

          page_matches(content, regex, &block).each do |match_text|
            match_data[:matches][match_text] = Version.new(match_text)
          end

          match_data
        end
      end
    end
  end
end
