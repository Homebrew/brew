# typed: true
# frozen_string_literal: true

module Homebrew
  module Livecheck
    module Strategy
      # The {Xorg} strategy identifies versions of software at x.org by
      # checking directory listing pages.
      #
      # X.Org URLs take one of the following formats, among several others:
      #
      # * `https://www.x.org/archive/individual/app/example-1.2.3.tar.bz2`
      # * `https://www.x.org/archive/individual/font/example-1.2.3.tar.bz2`
      # * `https://www.x.org/archive/individual/lib/libexample-1.2.3.tar.bz2`
      # * `https://ftp.x.org/archive/individual/lib/libexample-1.2.3.tar.bz2`
      # * `https://www.x.org/pub/individual/doc/example-1.2.3.tar.gz`
      #
      # The notable differences between URLs are as follows:
      #
      # * `www.x.org` and `ftp.x.org` seem to be interchangeable (we prefer
      #   `www.x.org`).
      # * `/archive/` is the current top-level directory and `/pub/` will
      #   redirect to the same URL using `/archive/` instead. (The strategy
      #   handles this replacement to avoid the redirection.)
      # * The `/individual/` directory contains a number of directories (e.g.
      #   app, data, doc, driver, font, lib, etc.) which contain a number of
      #   different archive files.
      #
      # Since this strategy ends up checking the same directory listing pages
      # for multiple formulae, we've included a simple method of page caching.
      # This prevents livecheck from fetching the same page more than once and
      # also dramatically speeds up these checks. Eventually we hope to
      # implement a more sophisticated page cache that all strategies using
      # {PageMatch} can use (allowing us to simplify this strategy accordingly).
      #
      # The default regex identifies versions in archive files found in `href`
      # attributes.
      #
      # @api public
      class Xorg
        NICE_NAME = "X.Org"

        # A `Regexp` used in determining if the strategy applies to the URL and
        # also as part of extracting the module name from the URL basename.
        MODULE_REGEX = /(?<module_name>.+)-\d+/i.freeze

        # A `Regexp` used to extract the module name from the URL basename.
        FILENAME_REGEX = /^#{MODULE_REGEX.source.strip}/i.freeze

        # The `Regexp` used to determine if the strategy applies to the URL.
        URL_MATCH_REGEX = %r{
          ^https?://(?:[^/]+?\.)* # Scheme and any leading subdomains
          (?:x\.org/(?:[^/]+/)*individual/(?:[^/]+/)*#{MODULE_REGEX.source.strip}
          |freedesktop\.org/(?:archive|dist|software)/(?:[^/]+/)*#{MODULE_REGEX.source.strip})
        }ix.freeze

        # Used to cache page content, so we don't fetch the same pages
        # repeatedly.
        @page_data = {}

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

          file_name = File.basename(url)
          match = file_name.match(FILENAME_REGEX)
          return values if match.blank?

          # /pub/ URLs redirect to the same URL with /archive/, so we replace
          # it to avoid the redirection. Removing the filename from the end of
          # the URL gives us the relevant directory listing page.
          values[:url] = url.sub("x.org/pub/", "x.org/archive/").delete_suffix(file_name)

          regex_name = Regexp.escape(T.must(match[:module_name])).gsub("\\-", "-")

          # Example regex: `/href=.*?example[._-]v?(\d+(?:\.\d+)+)\.t/i`
          values[:regex] = /href=.*?#{regex_name}[._-]v?(\d+(?:\.\d+)+)\.t/i

          values
        end

        # Generates a URL and regex (if one isn't provided) and checks the
        # content at the URL for new versions (using the regex for matching).
        #
        # The behavior in this method for matching text in the content using a
        # regex is copied and modified from the {PageMatch} strategy, so that
        # we can add some simple page caching. If this behavior is expanded to
        # apply to all strategies that use {PageMatch} to identify versions,
        # then this strategy can be brought in line with the others.
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
          generated_url = generated[:url]

          # Use the cached page content to avoid duplicate fetches
          cached_content = @page_data[generated_url]
          match_data = PageMatch.find_versions(
            url:              generated_url,
            regex:            regex || generated[:regex],
            provided_content: cached_content,
            **unused,
            &block
          )

          # Cache any new page content
          @page_data[generated_url] = match_data[:content] if match_data[:content].present?

          match_data
        end
      end
    end
  end
end
