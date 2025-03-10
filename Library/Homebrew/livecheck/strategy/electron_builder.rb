# typed: strict
# frozen_string_literal: true

require "livecheck/strategic"

module Homebrew
  module Livecheck
    module Strategy
      # The {ElectronBuilder} strategy fetches content at a URL and parses it
      # as an electron-builder appcast in YAML format.
      #
      # This strategy is not applied automatically and it's necessary to use
      # `strategy :electron_builder` in a `livecheck` block to apply it.
      class ElectronBuilder
        extend Strategic

        NICE_NAME = "electron-builder"

        # A priority of zero causes livecheck to skip the strategy. We do this
        # for {ElectronBuilder} so we can selectively apply it when appropriate.
        PRIORITY = 0

        # The `Regexp` used to determine if the strategy applies to the URL.
        URL_MATCH_REGEX = %r{^https?://.+/[^/]+\.ya?ml(?:\?[^/?]+)?$}i

        # Whether the strategy can be applied to the provided URL.
        #
        # @param url [String] the URL to match against
        sig { override.params(url: String).returns(T::Boolean) }
        def self.match?(url)
          URL_MATCH_REGEX.match?(url)
        end

        # Checks the YAML content at the URL for new versions.
        #
        # @param url [String] the URL of the content to check
        # @param regex [Regexp, nil] a regex used for matching versions
        # @param provided_content [String, nil] content to use in place of
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
          if regex.present? && !block_given?
            raise ArgumentError,
                  "#{Utils.demodulize(name)} only supports a regex when using a `strategy` block"
          end

          Yaml.find_versions(
            url:,
            regex:,
            provided_content:,
            options:,
            &block || proc { |yaml| yaml["version"] }
          )
        end
      end
    end
  end
end
