# typed: strict
# frozen_string_literal: true

require "livecheck/strategic"

module Homebrew
  module Livecheck
    module Strategy
      # The {Sourceforge} strategy identifies versions of software at
      # sourceforge.net by checking a project's RSS feed.
      #
      # SourceForge URLs take a few different formats:
      #
      # * `https://downloads.sourceforge.net/project/example/example-1.2.3.tar.gz`
      # * `https://svn.code.sf.net/p/example/code/trunk`
      # * `:pserver:anonymous:@example.cvs.sourceforge.net:/cvsroot/example`
      #
      # The RSS feed for a project contains the most recent release archives
      # and while this is fine for most projects, this approach has some
      # shortcomings. Some project releases involve so many files that the one
      # we're interested in isn't present in the feed content. Some projects
      # contain additional software and the archive we're interested in is
      # pushed out of the feed (especially if it hasn't been updated recently).
      #
      # Usually we address this situation by adding a `livecheck` block to
      # the formula/cask that checks the page for the relevant directory in the
      # project instead. In this situation, it's necessary to use
      # `strategy :page_match` to prevent the {Sourceforge} stratgy from
      # being used.
      #
      # The default regex matches within `url` attributes in the RSS feed
      # and identifies versions within directory names or filenames.
      #
      # @api public
      class Sourceforge
        extend Strategic

        NICE_NAME = "SourceForge"

        # The `Regexp` used to determine if the strategy applies to the URL.
        URL_MATCH_REGEX = %r{
          ^https?://(?:[^/]+?\.)*(?:sourceforge|sf)\.net
          (?:/projects?/(?<project_name>[^/]+)/
          |/p/(?<project_name>[^/]+)/
          |(?::/cvsroot)?/(?<project_name>[^/]+))
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

          match = url.match(URL_MATCH_REGEX)
          return values if match.blank?

          # Don't generate a URL if the URL already points to the RSS feed
          unless url.match?(%r{/rss(?:/?$|\?)})
            values[:url] = "https://sourceforge.net/projects/#{match[:project_name]}/rss"
          end

          regex_name = Regexp.escape(T.must(match[:project_name])).gsub("\\-", "-")

          # It may be possible to improve the generated regex but there's quite
          # a bit of variation between projects and it can be challenging to
          # create something that works for most URLs.
          values[:regex] = %r{url=.*?/#{regex_name}/files/.*?[-_/](\d+(?:[-.]\d+)+)[-_/%.]}i

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
            url:     generated[:url] || url,
            regex:   regex || generated[:regex],
            options:,
            &block
          )
        end
      end
    end
  end
end
