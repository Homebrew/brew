# typed: strict
# frozen_string_literal: true

require "livecheck/strategic"

module Homebrew
  module Livecheck
    module Strategy
      # The {Cpan} strategy identifies versions of software at
      # cpan.metacpan.org by checking directory listing pages.
      #
      # CPAN URLs take the following formats:
      #
      # * `https://cpan.metacpan.org/authors/id/H/HO/HOMEBREW/Brew-v1.2.3.tar.gz`
      # * `https://cpan.metacpan.org/authors/id/H/HO/HOMEBREW/brew/brew-v1.2.3.tar.gz`
      #
      # In these examples, `HOMEBREW` is the author name and the preceding `H`
      # and `HO` directories correspond to the first letter(s). Some authors
      # also store files in subdirectories, as in the second example above.
      #
      # @api public
      class Cpan
        extend Strategic

        NICE_NAME = "CPAN"

        # The `Regexp` used to determine if the strategy applies to the URL.
        URL_MATCH_REGEX = %r{
          ^https?://cpan\.metacpan\.org
          (?<path>/authors/id(?:/[^/]+){3,}/) # Path before the filename
          (?<prefix>[^/]+) # Filename text before the version
          -v?\d+(?:\.\d+)* # The numeric version
          (?<suffix>[^/]+) # Filename text after the version
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
        # Some of these values act as defaults and can be overridden in a
        # `livecheck` block.
        #
        # @param url [String] the URL used to generate values
        sig { params(url: String).returns(T::Hash[Symbol, T.untyped]) }
        def self.generate_input_values(url)
          values = {}

          match = url.match(URL_MATCH_REGEX)
          return values if match.blank?

          # The directory listing page where the archive files are found
          values[:url] = "https://cpan.metacpan.org#{match[:path]}"

          regex_prefix = Regexp.escape(T.must(match[:prefix])).gsub("\\-", "-")

          # Use `\.t` instead of specific tarball extensions (e.g. .tar.gz)
          suffix = T.must(match[:suffix]).sub(Strategy::TARBALL_EXTENSION_REGEX, ".t")
          regex_suffix = Regexp.escape(suffix).gsub("\\-", "-")

          # Example regex: `/href=.*?Brew[._-]v?(\d+(?:\.\d+)*)\.t/i`
          values[:regex] = /href=.*?#{regex_prefix}[._-]v?(\d+(?:\.\d+)*)#{regex_suffix}/i

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
