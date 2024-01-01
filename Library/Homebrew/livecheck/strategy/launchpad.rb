# typed: true
# frozen_string_literal: true

module Homebrew
  module Livecheck
    module Strategy
      # The {Launchpad} strategy identifies versions of software at
      # launchpad.net by checking the main page for a project.
      #
      # Launchpad URLs take a variety of formats but all the current formats
      # contain the project name as the first part of the URL path:
      #
      # * `https://launchpad.net/example/1.2/1.2.3/+download/example-1.2.3.tar.gz`
      # * `https://launchpad.net/example/trunk/1.2.3/+download/example-1.2.3.tar.gz`
      # * `https://code.launchpad.net/example/1.2/1.2.3/+download/example-1.2.3.tar.gz`
      #
      # The default regex identifies the latest version within an HTML element
      # found on the main page for a project:
      #
      # <pre><div class="version">
      #   Latest version is 1.2.3
      # </div></pre>
      #
      # @api public
      class Launchpad
        # The `Regexp` used to determine if the strategy applies to the URL.
        URL_MATCH_REGEX = %r{
          ^https?://(?:[^/]+?\.)*launchpad\.net
          /(?<project_name>[^/]+) # The Launchpad project name
        }ix.freeze

        # The default regex used to identify the latest version when a regex
        # isn't provided.
        DEFAULT_REGEX = %r{class="[^"]*version[^"]*"[^>]*>\s*Latest version is (.+)\s*</}.freeze

        # Whether the strategy can be applied to the provided URL.
        #
        # @param url [String] the URL to match against
        # @return [Boolean]
        sig { params(url: String).returns(T::Boolean) }
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

          # The main page for the project on Launchpad
          values[:url] = "https://launchpad.net/#{match[:project_name]}/"

          values
        end

        # Generates a URL and regex (if one isn't provided) and passes them
        # to {PageMatch.find_versions} to identify versions in the content.
        #
        # @param url [String] the URL of the content to check
        # @param regex [Regexp] a regex used for matching versions in content
        # @return [Hash]
        sig {
          params(
            url:    String,
            regex:  Regexp,
            unused: T.nilable(T::Hash[Symbol, T.untyped]),
            block:  T.nilable(Proc),
          ).returns(T::Hash[Symbol, T.untyped])
        }
        def self.find_versions(url:, regex: DEFAULT_REGEX, **unused, &block)
          generated = generate_input_values(url)

          PageMatch.find_versions(url: generated[:url], regex: regex, **unused, &block)
        end
      end
    end
  end
end
