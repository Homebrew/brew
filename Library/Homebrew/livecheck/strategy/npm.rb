# typed: strict
# frozen_string_literal: true

require "livecheck/strategic"

module Homebrew
  module Livecheck
    module Strategy
      # The {Npm} strategy identifies versions of software at
      # registry.npmjs.org by checking the listed versions for a package.
      #
      # npm URLs take one of the following formats:
      #
      # * `https://registry.npmjs.org/example/-/example-1.2.3.tgz`
      # * `https://registry.npmjs.org/@example/example/-/example-1.2.3.tgz`
      #
      # The default regex matches URLs in the `href` attributes of version tags
      # on the "Versions" tab of the package page.
      #
      # @api public
      class Npm
        extend Strategic

        NICE_NAME = "npm"

        # The `Regexp` used to determine if the strategy applies to the URL.
        URL_MATCH_REGEX = %r{
          ^https?://registry\.npmjs\.org
          /(?<package_name>.+?)/-/ # The npm package name
        }ix

        # Whether the strategy can be applied to the provided URL.
        #
        # @param url [String] the URL to match against
        # @return [Boolean]
        sig { override.params(url: String).returns(T::Boolean) }
        def self.match?(url)
          URL_MATCH_REGEX.match?(url)
        end

        # Extracts information from a provided URL and uses it to generate
        # various input values used by the strategy to check for new versions.
        # Some of these values act as defaults and can be overridden in a
        # `livecheck` block.
        #
        # @param url [String] the URL used to generate values
        # @return [Hash]
        sig { params(url: String).returns(T::Hash[Symbol, T.untyped]) }
        def self.generate_input_values(url)
          values = {}

          match = url.match(URL_MATCH_REGEX)
          return values if match.blank?

          values[:url] = "https://www.npmjs.com/package/#{match[:package_name]}?activeTab=versions"

          regex_name = Regexp.escape(T.must(match[:package_name])).gsub("\\-", "-")

          # Example regexes:
          # * `%r{href=.*?/package/example/v/(\d+(?:\.\d+)+)"}i`
          # * `%r{href=.*?/package/@example/example/v/(\d+(?:\.\d+)+)"}i`
          values[:regex] = %r{href=.*?/package/#{regex_name}/v/(\d+(?:\.\d+)+)"}i

          values
        end

        # Generates a URL and regex (if one isn't provided) and passes them
        # to {PageMatch.find_versions} to identify versions in the content.
        #
        # @param url [String] the URL of the content to check
        # @param regex [Regexp] a regex used for matching versions in content
        # @param options [Options] options to modify behavior
        # @return [Hash]
        sig {
          override(allow_incompatible: true).params(
            url:     String,
            regex:   T.nilable(Regexp),
            options: Options,
            block:   T.nilable(Proc),
          ).returns(T::Hash[Symbol, T.anything])
        }
        def self.find_versions(url:, regex: nil, options: Options.new, &block)
          generated = generate_input_values(url)

          PageMatch.find_versions(
            url:     generated[:url],
            regex:   regex || generated[:regex],
            options:,
            &block
          )
        end
      end
    end
  end
end
