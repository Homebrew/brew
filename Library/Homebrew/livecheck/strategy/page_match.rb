# typed: strict
# frozen_string_literal: true

require "livecheck/strategic"

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
      # The {find_versions} method can be used within other strategies, to
      # handle the process of identifying version text in content.
      #
      # @api public
      class PageMatch
        extend Strategic

        NICE_NAME = "Page match"

        # A priority of zero causes livecheck to skip the strategy. We do this
        # for {PageMatch} so we can selectively apply it only when a regex is
        # provided in a `livecheck` block.
        PRIORITY = 0

        # The `Regexp` used to determine if the strategy applies to the URL.
        URL_MATCH_REGEX = %r{^https?://}i

        # Whether the strategy can be applied to the provided URL.
        # {PageMatch} will technically match any HTTP URL but is only
        # usable with a `livecheck` block containing a regex.
        #
        # @param url [String] the URL to match against
        # @return [Boolean]
        sig { override.params(url: String).returns(T::Boolean) }
        def self.match?(url)
          URL_MATCH_REGEX.match?(url)
        end

        # Uses the regex to match text in the content or, if a block is
        # provided, passes the page content to the block to handle matching.
        # With either approach, an array of unique matches is returned.
        #
        # @param content [String] the page content to check
        # @param regex [Regexp, nil] a regex used for matching versions in the
        #   content
        # @return [Array]
        sig {
          params(
            content: String,
            regex:   T.nilable(Regexp),
            block:   T.nilable(Proc),
          ).returns(T::Array[String])
        }
        def self.versions_from_content(content, regex, &block)
          if block
            block_return_value = regex.present? ? yield(content, regex) : yield(content)
            return Strategy.handle_block_return(block_return_value)
          end

          return [] if regex.blank?

          content.scan(regex).filter_map do |match|
            case match
            when String
              match
            when Array
              match.first
            end
          end.uniq
        end

        # Checks the content at the URL for new versions, using the provided
        # regex for matching.
        #
        # @param url [String] the URL of the content to check
        # @param regex [Regexp, nil] a regex used for matching versions
        # @param provided_content [String, nil] page content to use in place of
        #   fetching via `Strategy#page_content`
        # @param options [Options] options to modify behavior
        # @return [Hash]
        sig {
          override.params(
            url:              String,
            regex:            T.nilable(Regexp),
            provided_content: T.nilable(String),
            options:          Options,
            block:            T.nilable(Proc),
          ).returns(T::Hash[Symbol, T.untyped])
        }
        def self.find_versions(url:, regex: nil, provided_content: nil, options: Options.new, &block)
          if regex.blank? && !block_given?
            raise ArgumentError, "#{Utils.demodulize(name)} requires a regex or `strategy` block"
          end

          match_data = { matches: {}, regex:, url: }
          return match_data if url.blank?

          content = if provided_content.is_a?(String)
            match_data[:cached] = true
            provided_content
          else
            match_data.merge!(Strategy.page_content(url, options:))
            match_data[:content]
          end
          return match_data if content.blank?

          versions_from_content(content, regex, &block).each do |match_text|
            match_data[:matches][match_text] = Version.new(match_text)
          end

          match_data
        end
      end
    end
  end
end
