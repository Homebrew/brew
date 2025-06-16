# typed: strict
# frozen_string_literal: true

require "livecheck/strategic"

module Homebrew
  module Livecheck
    module Strategy
      # The {Yaml} strategy fetches content at a URL, parses it as YAML and
      # provides the parsed data to a `strategy` block. If a regex is present
      # in the `livecheck` block, it should be passed as the second argument to
      # the `strategy` block.
      #
      # This is a generic strategy that doesn't contain any logic for finding
      # versions, as the structure of YAML data varies. Instead, a `strategy`
      # block must be used to extract version information from the YAML data.
      #
      # This strategy is not applied automatically and it is necessary to use
      # `strategy :yaml` in a `livecheck` block (in conjunction with a
      # `strategy` block) to use it.
      #
      # This strategy's {find_versions} method can be used in other strategies
      # that work with YAML content, so it should only be necessary to write
      # the version-finding logic that works with the parsed YAML data.
      #
      # @api public
      class Yaml
        extend Strategic

        NICE_NAME = "YAML"

        # A priority of zero causes livecheck to skip the strategy. We do this
        # for {Yaml} so we can selectively apply it only when a strategy block
        # is provided in a `livecheck` block.
        PRIORITY = 0

        # The `Regexp` used to determine if the strategy applies to the URL.
        URL_MATCH_REGEX = %r{^https?://}i

        # Whether the strategy can be applied to the provided URL.
        # {Yaml} will technically match any HTTP URL but is only usable with
        # a `livecheck` block containing a `strategy` block.
        #
        # @param url [String] the URL to match against
        # @return [Boolean]
        sig { override.params(url: String).returns(T::Boolean) }
        def self.match?(url)
          URL_MATCH_REGEX.match?(url)
        end

        # Parses YAML text and returns the parsed data.
        # @param content [String] the YAML text to parse
        sig { params(content: String).returns(T.untyped) }
        def self.parse_yaml(content)
          require "yaml"

          begin
            YAML.safe_load(content, permitted_classes: [Date, Time])
          rescue Psych::SyntaxError
            raise "Content could not be parsed as YAML."
          end
        end

        # Parses YAML text and identifies versions using a `strategy` block.
        # If a regex is provided, it will be passed as the second argument to
        # the  `strategy` block (after the parsed YAML data).
        # @param content [String] the YAML text to parse and check
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
        def self.versions_from_content(content, regex = nil, &block)
          return [] if content.blank? || !block_given?

          yaml = parse_yaml(content)
          return [] if yaml.blank?

          block_return_value = if regex.present?
            yield(yaml, regex)
          elsif block.arity == 2
            raise "Two arguments found in `strategy` block but no regex provided."
          else
            yield(yaml)
          end
          Strategy.handle_block_return(block_return_value)
        end

        # Checks the YAML content at the URL for versions, using the provided
        # `strategy` block to extract version information.
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
          ).returns(T::Hash[Symbol, T.anything])
        }
        def self.find_versions(url:, regex: nil, provided_content: nil, options: Options.new, &block)
          raise ArgumentError, "#{Utils.demodulize(name)} requires a `strategy` block" unless block_given?

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
