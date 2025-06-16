# typed: strict
# frozen_string_literal: true

require "livecheck/strategic"

module Homebrew
  module Livecheck
    module Strategy
      # The {Gnu} strategy identifies versions of software at gnu.org by
      # checking directory listing pages.
      #
      # GNU URLs use a variety of formats:
      #
      # * Archive file URLs:
      #   * `https://ftp.gnu.org/gnu/example/example-1.2.3.tar.gz`
      #   * `https://ftp.gnu.org/gnu/example/1.2.3/example-1.2.3.tar.gz`
      # * Homepage URLs:
      #   * `https://www.gnu.org/software/example/`
      #   * `https://example.gnu.org`
      #
      # There are other URL formats that this strategy currently doesn't
      # support:
      #
      # * `https://ftp.gnu.org/non-gnu/example/source/feature/1.2.3/example-1.2.3.tar.gz`
      # * `https://savannah.nongnu.org/download/example/example-1.2.3.tar.gz`
      # * `https://download.savannah.gnu.org/releases/example/example-1.2.3.tar.gz`
      # * `https://download.savannah.nongnu.org/releases/example/example-1.2.3.tar.gz`
      #
      # The default regex identifies versions in archive files found in `href`
      # attributes.
      #
      # @api public
      class Gnu
        extend Strategic

        NICE_NAME = "GNU"

        # The `Regexp` used to determine if the strategy applies to the URL.
        URL_MATCH_REGEX = T.let(%r{
          ^https?://
          (?:(?:[^/]+?\.)*gnu\.org/(?:gnu|software)/(?<project_name>[^/]+)/
          |(?<project_name>[^/]+)\.gnu\.org/?$)
        }ix, Regexp)

        # Whether the strategy can be applied to the provided URL.
        #
        # @param url [String] the URL to match against
        # @return [Boolean]
        sig { override.params(url: String).returns(T::Boolean) }
        def self.match?(url)
          URL_MATCH_REGEX.match?(url) && url.exclude?("savannah.")
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

          # The directory listing page for the project's files
          values[:url] = "https://ftp.gnu.org/gnu/#{match[:project_name]}/"

          regex_name = Regexp.escape(T.must(match[:project_name])).gsub("\\-", "-")

          # The default regex consists of the following parts:
          # * `href=.*?`: restricts matching to URLs in `href` attributes
          # * The project name
          # * `[._-]`: the generic delimiter between project name and version
          # * `v?(\d+(?:\.\d+)*)`: the numeric version
          # * `(?:\.[a-z]+|/)`: the file extension (a trailing delimiter)
          #
          # Example regex: `%r{href=.*?example[._-]v?(\d+(?:\.\d+)*)(?:\.[a-z]+|/)}i`
          values[:regex] = %r{href=.*?#{regex_name}[._-]v?(\d+(?:\.\d+)*)(?:\.[a-z]+|/)}i

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
