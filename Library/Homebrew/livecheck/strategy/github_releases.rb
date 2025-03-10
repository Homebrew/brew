# typed: strict
# frozen_string_literal: true

require "livecheck/strategic"

module Homebrew
  module Livecheck
    module Strategy
      # The {GithubReleases} strategy identifies versions of software at
      # github.com by checking a repository's recent releases using the
      # GitHub API.
      #
      # GitHub URLs take a few different formats:
      #
      # * `https://github.com/example/example/releases/download/1.2.3/example-1.2.3.tar.gz`
      # * `https://github.com/example/example/archive/v1.2.3.tar.gz`
      # * `https://github.com/downloads/example/example/example-1.2.3.tar.gz`
      #
      # {GithubReleases} should only be used when the upstream repository has
      # releases for suitable versions and the strategy is necessary or
      # appropriate (e.g. the formula/cask uses a release asset and the
      # {GithubLatest} strategy isn't sufficient to identify the newest version.
      # The strategy can only be applied by using `strategy :github_releases`
      # in a `livecheck` block.
      #
      # The default regex identifies versions like `1.2.3`/`v1.2.3` in each
      # release's tag or title. This is a common tag format but a modified
      # regex can be provided in a `livecheck` block to override the default
      # if a repository uses a different format (e.g. `1.2.3d`, `1.2.3-4`,
      # etc.).
      #
      # @api public
      class GithubReleases
        extend Strategic

        NICE_NAME = "GitHub - Releases"

        # A priority of zero causes livecheck to skip the strategy. We do this
        # for {GithubReleases} so we can selectively apply the strategy using
        # `strategy :github_releases` in a `livecheck` block.
        PRIORITY = 0

        # The `Regexp` used to determine if the strategy applies to the URL.
        URL_MATCH_REGEX = %r{
          ^https?://github\.com
          /(?:downloads/)?(?<username>[^/]+) # The GitHub username
          /(?<repository>[^/]+)              # The GitHub repository name
        }ix

        # The default regex used to identify a version from a tag when a regex
        # isn't provided.
        DEFAULT_REGEX = /v?(\d+(?:\.\d+)+)/i

        # Keys in the release JSON that could contain the version.
        # The tag name is checked first, to better align with the {Git}
        # strategy.
        VERSION_KEYS = T.let(["tag_name", "name"].freeze, T::Array[String])

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

          match = url.delete_suffix(".git").match(URL_MATCH_REGEX)
          return values if match.blank?

          values[:url] = "#{GitHub::API_URL}/repos/#{match[:username]}/#{match[:repository]}/releases"
          values[:username] = match[:username]
          values[:repository] = match[:repository]

          values
        end

        # Uses a regex to match versions from release JSON or, if a block is
        # provided, passes the JSON to the block to handle matching. With
        # either approach, an array of unique matches is returned.
        #
        # @param content [Array, Hash] array of releases or a single release
        # @param regex [Regexp] a regex used for matching versions in the
        # content
        # @param block [Proc, nil] a block to match the content
        # @return [Array]
        sig {
          params(
            content: T.any(T::Array[T::Hash[String, T.untyped]], T::Hash[String, T.untyped]),
            regex:   Regexp,
            block:   T.nilable(Proc),
          ).returns(T::Array[String])
        }
        def self.versions_from_content(content, regex, &block)
          if block.present?
            block_return_value = yield(content, regex)
            return Strategy.handle_block_return(block_return_value)
          end

          content = [content] unless content.is_a?(Array)
          content.compact_blank.filter_map do |release|
            next if release["draft"] || release["prerelease"]

            value = T.let(nil, T.nilable(String))
            VERSION_KEYS.find do |key|
              match = release[key]&.match(regex)
              next if match.blank?

              value = match[1]
            end
            value
          end.uniq
        end

        # Generates the GitHub API URL for the repository's recent releases
        # and identifies versions from the JSON response.
        #
        # @param url [String] the URL of the content to check
        # @param regex [Regexp] a regex used for matching versions in content
        # @param options [Options] options to modify behavior
        # @return [Hash]
        sig {
          override(allow_incompatible: true).params(
            url:     String,
            regex:   Regexp,
            options: Options,
            block:   T.nilable(Proc),
          ).returns(T::Hash[Symbol, T.anything])
        }
        def self.find_versions(url:, regex: DEFAULT_REGEX, options: Options.new, &block)
          match_data = { matches: {}, regex:, url: }

          generated = generate_input_values(url)
          return match_data if generated.blank?

          match_data[:url] = generated[:url]

          releases = GitHub::API.open_rest(generated[:url])
          versions_from_content(releases, regex, &block).each do |match_text|
            match_data[:matches][match_text] = Version.new(match_text)
          end

          match_data
        end
      end
    end
    GitHubReleases = Homebrew::Livecheck::Strategy::GithubReleases
  end
end
