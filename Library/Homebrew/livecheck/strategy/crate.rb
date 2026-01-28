# typed: strict
# frozen_string_literal: true

require "livecheck/strategic"

module Homebrew
  module Livecheck
    module Strategy
      # The {Crate} strategy identifies versions of a Rust crate by checking
      # the information from the `versions` API endpoint.
      #
      # Crate URLs have the following format:
      #   `https://static.crates.io/crates/example/example-1.2.3.crate`
      #
      # The default regex identifies versions like `1.2.3`/`v1.2.3` from the
      # version `num` field. This is a common version format but a different
      # regex can be provided in a `livecheck` block to override the default
      # if a package uses a different format (e.g. `1.2.3d`, `1.2.3-4`, etc.).
      #
      # @api public
      class Crate
        extend Strategic

        # The default regex used to identify versions when a regex isn't
        # provided.
        DEFAULT_REGEX = /^v?(\d+(?:\.\d+)+)$/i

        # The default `strategy` block used to extract version information when
        # a `strategy` block isn't provided.
        DEFAULT_BLOCK = T.let(proc do |json, regex|
          json["versions"]&.map do |version|
            next if version["yanked"]
            next unless (match = version["num"]&.match(regex))

            match[1]
          end
        end.freeze, T.proc.params(
          arg0: T::Hash[String, T.anything],
          arg1: Regexp,
        ).returns(T.any(String, T::Array[String])))

        # The `Regexp` used to determine if the strategy applies to the URL.
        URL_MATCH_REGEX = %r{
          ^https?://static\.crates\.io/crates
          /(?<package>[^/]+) # The name of the package
          /.+\.crate # The crate filename
        }ix

        # Whether the strategy can be applied to the provided URL.
        #
        # @param url [String] the URL to match against
        sig { override.params(url: String).returns(T::Boolean) }
        def self.match?(url)
          URL_MATCH_REGEX.match?(url)
        end

        # Extracts information from a provided URL and uses it to generate
        # various input values used by the strategy to check for new versions.
        #
        # @param url [String] the URL used to generate values
        sig { params(url: String).returns(T::Hash[Symbol, T.untyped]) }
        def self.generate_input_values(url)
          values = {}
          return values unless (match = url.match(URL_MATCH_REGEX))

          values[:url] = "https://crates.io/api/v1/crates/#{match[:package]}/versions"

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

          Json.versions_from_content(content, regex || DEFAULT_REGEX, &block || DEFAULT_BLOCK).each do |match_text|
            match_data[:matches][match_text] = Version.new(match_text)
          end

          match_data
        end
      end
    end
  end
end
