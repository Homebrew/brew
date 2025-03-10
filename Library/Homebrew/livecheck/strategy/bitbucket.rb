# typed: strict
# frozen_string_literal: true

require "livecheck/strategic"

module Homebrew
  module Livecheck
    module Strategy
      # The {Bitbucket} strategy identifies versions of software at
      # bitbucket.org by checking a repository's available downloads.
      #
      # Bitbucket URLs generally take one of the following formats:
      #
      # * `https://bitbucket.org/example/example/get/1.2.3.tar.gz`
      # * `https://bitbucket.org/example/example/downloads/example-1.2.3.tar.gz`
      #
      # The `/get/` archive files are simply automated snapshots of the files
      # for a given tag. The `/downloads/` archive files are files that have
      # been uploaded instead.
      #
      # It's also possible for an archive to come from a repository's wiki,
      # like:
      # `https://bitbucket.org/example/example/wiki/downloads/example-1.2.3.zip`.
      # This scenario is handled by this strategy as well and the `path` in
      # this example would be `example/example/wiki` (instead of
      # `example/example` with the previous URLs).
      #
      # The default regex identifies versions in archive files found in `href`
      # attributes.
      #
      # @api public
      class Bitbucket
        extend Strategic

        # The `Regexp` used to determine if the strategy applies to the URL.
        URL_MATCH_REGEX = %r{
          ^https?://bitbucket\.org
          /(?<path>.+?) # The path leading up to the get or downloads part
          /(?<dl_type>get|downloads) # An indicator of the file download type
          /(?<prefix>(?:[^/]+?[_-])?) # Filename text before the version
          v?\d+(?:\.\d+)+ # The numeric version
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

          regex_prefix = Regexp.escape(T.must(match[:prefix])).gsub("\\-", "-")

          # `/get/` archives are Git tag snapshots, so we need to check that tab
          # instead of the main `/downloads/` page
          if match[:dl_type] == "get"
            values[:url] = "https://bitbucket.org/#{match[:path]}/downloads/?tab=tags"

            # Example tag regexes:
            # * `/<td[^>]*?class="name"[^>]*?>\s*v?(\d+(?:\.\d+)+)\s*?</im`
            # * `/<td[^>]*?class="name"[^>]*?>\s*abc-v?(\d+(?:\.\d+)+)\s*?</im`
            values[:regex] = /<td[^>]*?class="name"[^>]*?>\s*#{regex_prefix}v?(\d+(?:\.\d+)+)\s*?</im
          else
            values[:url] = "https://bitbucket.org/#{match[:path]}/downloads/"

            # Use `\.t` instead of specific tarball extensions (e.g. .tar.gz)
            suffix = T.must(match[:suffix]).sub(Strategy::TARBALL_EXTENSION_REGEX, ".t")
            regex_suffix = Regexp.escape(suffix).gsub("\\-", "-")

            # Example file regexes:
            # * `/href=.*?v?(\d+(?:\.\d+)+)\.t/i`
            # * `/href=.*?abc-v?(\d+(?:\.\d+)+)\.t/i`
            values[:regex] = /href=.*?#{regex_prefix}v?(\d+(?:\.\d+)+)#{regex_suffix}/i
          end

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
