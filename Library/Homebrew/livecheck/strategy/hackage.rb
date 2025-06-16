# typed: strict
# frozen_string_literal: true

require "livecheck/strategic"

module Homebrew
  module Livecheck
    module Strategy
      # The {Hackage} strategy identifies versions of software at
      # hackage.haskell.org by checking directory listing pages.
      #
      # Hackage URLs take one of the following formats:
      #
      # * `https://hackage.haskell.org/package/example-1.2.3/example-1.2.3.tar.gz`
      # * `https://downloads.haskell.org/~ghc/8.10.1/ghc-8.10.1-src.tar.xz`
      #
      # The default regex checks for the latest version in an `h3` heading element
      # with a format like `<h3>example-1.2.3/</h3>`.
      #
      # @api public
      class Hackage
        extend Strategic

        # A `Regexp` used in determining if the strategy applies to the URL and
        # also as part of extracting the package name from the URL basename.
        PACKAGE_NAME_REGEX = /(?<package_name>.+?)-\d+/i

        # A `Regexp` used to extract the package name from the URL basename.
        FILENAME_REGEX = /^#{PACKAGE_NAME_REGEX.source.strip}/i

        # A `Regexp` used in determining if the strategy applies to the URL.
        URL_MATCH_REGEX = %r{
          ^https?://(?:downloads|hackage)\.haskell\.org
          (?:/[^/]+)+ # Path before the filename
          #{PACKAGE_NAME_REGEX.source.strip}
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

          match = File.basename(url).match(FILENAME_REGEX)
          return values if match.blank?

          # A page containing a directory listing of the latest source tarball
          values[:url] = "https://hackage.haskell.org/package/#{match[:package_name]}/src/"

          regex_name = Regexp.escape(T.must(match[:package_name])).gsub("\\-", "-")

          # Example regex: `%r{<h3>example-(.*?)/?</h3>}i`
          values[:regex] = %r{<h3>#{regex_name}-(.*?)/?</h3>}i

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
