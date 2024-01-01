# typed: true
# frozen_string_literal: true

module Homebrew
  module Livecheck
    module Strategy
      # The {Pypi} strategy identifies versions of software at pypi.org by
      # checking project pages for archive files.
      #
      # PyPI URLs have a standard format but the hexadecimal text between
      # `/packages/` and the filename varies:
      #
      # * `https://files.pythonhosted.org/packages/<hex>/<hex>/<long_hex>/example-1.2.3.tar.gz`
      #
      # As such, the default regex only targets the filename at the end of the
      # URL.
      #
      # @api public
      class Pypi
        NICE_NAME = "PyPI"

        # The `Regexp` used to extract the package name and suffix (e.g. file
        # extension) from the URL basename.
        FILENAME_REGEX = /
          (?<package_name>.+)- # The package name followed by a hyphen
          .*? # The version string
          (?<suffix>\.tar\.[a-z0-9]+|\.[a-z0-9]+)$ # Filename extension
        /ix.freeze

        # The `Regexp` used to determine if the strategy applies to the URL.
        URL_MATCH_REGEX = %r{
          ^https?://files\.pythonhosted\.org
          /packages
          (?:/[^/]+)+ # The hexadecimal paths before the filename
          /#{FILENAME_REGEX.source.strip} # The filename
        }ix.freeze

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

          match = File.basename(url).match(FILENAME_REGEX)
          return values if match.blank?

          # It's not technically necessary to have the `#files` fragment at the
          # end of the URL but it makes the debug output a bit more useful.
          values[:url] = "https://pypi.org/project/#{T.must(match[:package_name]).gsub(/%20|_/, "-")}/#files"

          # Use `\.t` instead of specific tarball extensions (e.g. .tar.gz)
          suffix = T.must(match[:suffix]).sub(Strategy::TARBALL_EXTENSION_REGEX, ".t")
          regex_suffix = Regexp.escape(suffix).gsub("\\-", "-")

          # Example regex: `%r{href=.*?/packages.*?/example[._-]v?(\d+(?:\.\d+)*(?:[._-]post\d+)?)\.t}i`
          regex_name = Regexp.escape(T.must(match[:package_name])).gsub("\\-", "-")
          values[:regex] =
            %r{href=.*?/packages.*?/#{regex_name}[._-]v?(\d+(?:\.\d+)*(?:[._-]post\d+)?)#{regex_suffix}}i

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
            regex:  T.nilable(Regexp),
            unused: T.nilable(T::Hash[Symbol, T.untyped]),
            block:  T.nilable(Proc),
          ).returns(T::Hash[Symbol, T.untyped])
        }
        def self.find_versions(url:, regex: nil, **unused, &block)
          generated = generate_input_values(url)

          PageMatch.find_versions(url: generated[:url], regex: regex || generated[:regex], **unused, &block)
        end
      end
    end
  end
end
