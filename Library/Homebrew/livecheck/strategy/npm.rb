# typed: strict
# frozen_string_literal: true

require "livecheck/strategic"

module Homebrew
  module Livecheck
    module Strategy
      # The {Npm} strategy identifies versions of software at
      # registry.npmjs.org by checking the latest version for a package.
      #
      # npm URLs take one of the following formats:
      #
      # * `https://registry.npmjs.org/example/-/example-1.2.3.tgz`
      # * `https://registry.npmjs.org/@example/example/-/example-1.2.3.tgz`
      #
      # @api public
      class Npm
        extend Strategic

        NICE_NAME = "npm"

        # The default `strategy` block used to extract version information when
        # a `strategy` block isn't provided.
        DEFAULT_BLOCK = T.let(proc do |json|
          json["version"]
        end.freeze, T.proc.params(
          arg0: T::Hash[String, T.anything],
        ).returns(T.any(String, T::Array[String])))

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
        #
        # @param url [String] the URL used to generate values
        # @return [Hash]
        sig { params(url: String).returns(T::Hash[Symbol, T.untyped]) }
        def self.generate_input_values(url)
          values = {}
          return values unless (match = url.match(URL_MATCH_REGEX))

          values[:url] = "https://registry.npmjs.org/#{URI.encode_www_form_component(match[:package_name])}/latest"

          values
        end

        # Generates a URL and checks the content at the URL for new versions
        # using {Json.versions_from_content}.
        #
        # @param url [String] the URL of the content to check
        # @param regex [Regexp, nil] a regex for matching versions in content
        # @param provided_content [String, nil] content to check instead of
        #   fetching
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
          match_data = { matches: {}, regex:, url: }
          match_data[:cached] = true if provided_content.is_a?(String)

          generated = generate_input_values(url)
          return match_data if generated.blank?

          match_data[:url] = generated[:url]

          content = if provided_content
            provided_content
          else
            match_data.merge!(Strategy.page_content(match_data[:url], options:))
            match_data[:content]
          end
          return match_data unless content

          Json.versions_from_content(content, regex, &block || DEFAULT_BLOCK).each do |match_text|
            match_data[:matches][match_text] = Version.new(match_text)
          end

          match_data
        end
      end
    end
  end
end
