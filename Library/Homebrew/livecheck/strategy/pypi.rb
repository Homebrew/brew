# typed: strict
# frozen_string_literal: true

require "livecheck/strategic"

module Homebrew
  module Livecheck
    module Strategy
      # The {Pypi} strategy identifies the newest version of a PyPI package by
      # checking the JSON API endpoint for the project and using the
      # `info.version` field from the response.
      #
      # PyPI URLs have a standard format:
      #   `https://files.pythonhosted.org/packages/<hex>/<hex>/<long_hex>/example-1.2.3.tar.gz`
      #
      # Upstream documentation for the PyPI JSON API can be found at:
      #   https://docs.pypi.org/api/json/#get-a-project
      #
      # @api public
      class Pypi
        extend Strategic

        NICE_NAME = "PyPI"

        # The default `strategy` block used to extract version information when
        # a `strategy` block isn't provided.
        DEFAULT_BLOCK = T.let(proc do |json, regex|
          version = json.dig("info", "version")
          next if version.blank?

          regex ? version[regex, 1] : version
        end.freeze, T.proc.params(
          json:  T::Hash[String, T.anything],
          regex: T.nilable(Regexp),
        ).returns(T.nilable(String)))

        # The `Regexp` used to extract the package name and suffix (e.g. file
        # extension) from the URL basename.
        FILENAME_REGEX = /
          (?<package_name>.+)- # The package name followed by a hyphen
          .*? # The version string
          (?<suffix>\.tar\.[a-z0-9]+|\.[a-z0-9]+)$ # Filename extension
        /ix

        # The `Regexp` used to determine if the strategy applies to the URL.
        URL_MATCH_REGEX = %r{
          ^https?://files\.pythonhosted\.org
          /packages
          (?:/[^/]+)+ # The hexadecimal paths before the filename
          /#{FILENAME_REGEX.source.strip} # The filename
        }ix

        # Whether the strategy can be applied to the provided URL.
        #
        # @param url [String] the URL to match against
        # @return [Boolean]
        sig { override.params(url: String).returns(T::Boolean) }
        def self.match?(url)
          URL_MATCH_REGEX.match?(url)
        end

        # Extracts the package name from the provided URL and uses it to
        # generate the PyPI JSON API URL for the project.
        #
        # @param url [String] the URL used to generate values
        # @return [Hash]
        sig { params(url: String).returns(T::Hash[Symbol, T.untyped]) }
        def self.generate_input_values(url)
          values = {}

          match = File.basename(url).match(FILENAME_REGEX)
          return values if match.blank?

          values[:url] = "https://pypi.org/pypi/#{T.must(match[:package_name]).gsub(/%20|_/, "-")}/json"

          values
        end

        # Generates a PyPI JSON API URL for the project and identifies new
        # versions using {Json#find_versions} with a block.
        #
        # @param url [String] the URL of the content to check
        # @param regex [Regexp] a regex used for matching versions in content
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

          generated = generate_input_values(url)
          return match_data if generated.blank?

          Json.find_versions(
            url:              generated[:url],
            regex:,
            provided_content:,
            options:,
            &block || DEFAULT_BLOCK
          )
        end
      end
    end
  end
end
