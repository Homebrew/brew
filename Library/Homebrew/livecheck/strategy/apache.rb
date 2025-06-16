# typed: strict
# frozen_string_literal: true

require "livecheck/strategic"

module Homebrew
  module Livecheck
    module Strategy
      # The {Apache} strategy identifies versions of software at apache.org
      # by checking directory listing pages.
      #
      # Most Apache URLs start with `https://www.apache.org/dyn/` and include
      # a `filename` or `path` query string parameter where the value is a
      # path to a file. The path takes one of the following formats:
      #
      # * `example/1.2.3/example-1.2.3.tar.gz`
      # * `example/example-1.2.3/example-1.2.3.tar.gz`
      # * `example/example-1.2.3-bin.tar.gz`
      #
      # This strategy also handles a few common mirror/backup URLs where the
      # path is provided outside of a query string parameter (e.g.
      # `https://archive.apache.org/dist/example/1.2.3/example-1.2.3.tar.gz`).
      #
      # When the path contains a version directory (e.g. `/1.2.3/`,
      # `/example-1.2.3/`, etc.), the default regex matches numeric versions
      # in directory names. Otherwise, the default regex matches numeric
      # versions in filenames.
      #
      # @api public
      class Apache
        extend Strategic

        # The `Regexp` used to determine if the strategy applies to the URL.
        URL_MATCH_REGEX = %r{
          ^https?://
          (?:www\.apache\.org/dyn/.+(?:path|filename)=/?|
          archive\.apache\.org/dist/|
          dlcdn\.apache\.org/|
          downloads\.apache\.org/)
          (?<path>.+?)/      # Path to directory of files or version directories
          (?<prefix>[^/]*?)  # Any text in filename or directory before version
          v?\d+(?:\.\d+)+    # The numeric version
          (?<suffix>/|[^/]*) # Any text in filename or directory after version
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

          # Example URL: `https://archive.apache.org/dist/example/`
          values[:url] = "https://archive.apache.org/dist/#{match[:path]}/"

          regex_prefix = Regexp.escape(match[:prefix] || "").gsub("\\-", "-")

          # Use `\.t` instead of specific tarball extensions (e.g. .tar.gz)
          suffix = match[:suffix]&.sub(Strategy::TARBALL_EXTENSION_REGEX, ".t")
          regex_suffix = Regexp.escape(suffix || "").gsub("\\-", "-")

          # Example directory regex: `%r{href=["']?v?(\d+(?:\.\d+)+)/}i`
          # Example file regexes:
          # * `/href=["']?example-v?(\d+(?:\.\d+)+)\.t/i`
          # * `/href=["']?example-v?(\d+(?:\.\d+)+)-bin\.zip/i`
          values[:regex] = /href=["']?#{regex_prefix}v?(\d+(?:\.\d+)+)#{regex_suffix}/i

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
