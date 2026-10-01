# typed: strict
# frozen_string_literal: true

require "livecheck/strategic"

module Homebrew
  module Livecheck
    module Strategy
      # The {RubyGems} strategy identifies the newest version of a RubyGems
      # package by checking the latest version API endpoint for the gem.
      #
      # RubyGems URLs have a standard format:
      #   `https://rubygems.org/downloads/example-1.2.3.gem`
      #
      # @api public
      class RubyGems
        extend Strategic

        # The default `strategy` block used to extract version information when
        # a `strategy` block isn't provided.
        DEFAULT_BLOCK = T.let(proc do |json|
          json["version"]
        end.freeze, T.proc.params(
          arg0: T::Hash[String, T.anything],
        ).returns(T.any(String, T::Array[String])))

        FILENAME_REGEX = /
          (?<gem_name>.+)- # The gem name followed by a hyphen
          (?<version>\d+(?:\.[0-9A-Za-z]+)*) # The version string
          (?:-(?<platform>.+))? # The optional platform
          \.gem$
        /ix

        # The `Regexp` used to determine if the strategy applies to the URL.
        URL_MATCH_REGEX = %r{
          ^https?://rubygems\.org
          /(?:downloads|gems/[^/]+/versions)
          /#{FILENAME_REGEX.source.strip} # The gem filename
        }ix

        # Whether the strategy can be applied to the provided URL.
        #
        # @param url [String] the URL to match against
        # @return [Boolean]
        sig { override.params(url: String).returns(T::Boolean) }
        def self.match?(url)
          URL_MATCH_REGEX.match?(url)
        end

        # Extracts the gem name from the provided URL and uses it to generate
        # the RubyGems latest version API URL for the gem.
        #
        # @param url [String] the URL used to generate values
        # @return [Hash]
        sig { params(url: String).returns(T::Hash[Symbol, T.untyped]) }
        def self.generate_input_values(url)
          values = {}
          return values unless (match = url.match(URL_MATCH_REGEX))
          return values unless (gem_name = match[:gem_name])

          values[:url] = "https://rubygems.org/api/v1/versions/" \
                         "#{URI.encode_www_form_component(gem_name)}/latest.json"

          values
        end

        # Generates a RubyGems latest version API URL for the gem and
        # identifies new versions using {Json#find_versions} with a block.
        #
        # @param url [String] the URL of the content to check
        # @param regex [Regexp, nil] a regex for matching versions in content
        # @param content [String, nil] content to check instead of fetching
        # @param options [Options] options to modify behavior
        # @return [Hash]
        sig {
          override.params(
            url:     String,
            regex:   T.nilable(Regexp),
            content: T.nilable(String),
            options: Options,
            block:   T.nilable(Proc),
          ).returns(T::Hash[Symbol, T.anything])
        }
        def self.find_versions(url:, regex: nil, content: nil, options: Options.new, &block)
          match_data = { matches: {}, regex:, url: }

          generated = generate_input_values(url)
          return match_data if generated.blank?

          Json.find_versions(
            url:     generated[:url],
            regex:,
            content:,
            options:,
            &block || DEFAULT_BLOCK
          )
        end
      end
    end
  end
end
