# typed: true
# frozen_string_literal: true

module Homebrew
  module Livecheck
    module Strategy
      # The {ElectronBuilder} strategy fetches content at a URL and parses it
      # as an electron-builder appcast in YAML format.
      #
      # This strategy is not applied automatically and it's necessary to use
      # `strategy :electron_builder` in a `livecheck` block to apply it.
      #
      # @api private
      class ElectronBuilder
        NICE_NAME = "electron-builder"

        # A priority of zero causes livecheck to skip the strategy. We do this
        # for {ElectronBuilder} so we can selectively apply it when appropriate.
        PRIORITY = 0

        # The `Regexp` used to determine if the strategy applies to the URL.
        URL_MATCH_REGEX = %r{^https?://.+/[^/]+\.ya?ml(?:\?[^/?]+)?$}i.freeze

        # Whether the strategy can be applied to the provided URL.
        #
        # @param url [String] the URL to match against
        # @return [Boolean]
        sig { params(url: String).returns(T::Boolean) }
        def self.match?(url)
          URL_MATCH_REGEX.match?(url)
        end

        # Checks the YAML content at the URL for new versions.
        #
        # @param url [String] the URL of the content to check
        # @param regex [Regexp, nil] a regex used for matching versions
        # @param provided_content [String, nil] content to use in place of
        #   fetching via `Strategy#page_content`
        # @return [Hash]
        sig {
          params(
            url:              String,
            regex:            T.nilable(Regexp),
            provided_content: T.nilable(String),
            unused:           T.nilable(T::Hash[Symbol, T.untyped]),
            block:            T.nilable(Proc),
          ).returns(T::Hash[Symbol, T.untyped])
        }
        def self.find_versions(url:, regex: nil, provided_content: nil, **unused, &block)
          if regex.present? && block.blank?
            raise ArgumentError,
                  "#{Utils.demodulize(T.must(name))} only supports a regex when using a `strategy` block"
          end

          Yaml.find_versions(
            url:              url,
            regex:            regex,
            provided_content: provided_content,
            **unused,
            &block || proc { |yaml| yaml["version"] }
          )
        end
      end
    end
  end
end
