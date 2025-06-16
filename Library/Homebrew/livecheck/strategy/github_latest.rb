# typed: strict
# frozen_string_literal: true

require "livecheck/strategic"

module Homebrew
  module Livecheck
    module Strategy
      # The {GithubLatest} strategy identifies versions of software at
      # github.com by checking a repository's "latest" release using the
      # GitHub API.
      #
      # GitHub URLs take a few different formats:
      #
      # * `https://github.com/example/example/releases/download/1.2.3/example-1.2.3.tar.gz`
      # * `https://github.com/example/example/archive/v1.2.3.tar.gz`
      # * `https://github.com/downloads/example/example/example-1.2.3.tar.gz`
      #
      # {GithubLatest} should only be used when the upstream repository has a
      # "latest" release for a suitable version and the strategy is necessary
      # or appropriate (e.g. the formula/cask uses a release asset or the
      # {Git} strategy returns an unreleased version). The strategy can only
      # be applied by using `strategy :github_latest` in a `livecheck` block.
      #
      # The default regex identifies versions like `1.2.3`/`v1.2.3` in a
      # release's tag or title. This is a common tag format but a modified
      # regex can be provided in a `livecheck` block to override the default
      # if a repository uses a different format (e.g. `1.2.3d`, `1.2.3-4`,
      # etc.).
      #
      # @api public
      class GithubLatest
        extend Strategic

        NICE_NAME = "GitHub - Latest"

        # A priority of zero causes livecheck to skip the strategy. We do this
        # for {GithubLatest} so we can selectively apply the strategy using
        # `strategy :github_latest` in a `livecheck` block.
        PRIORITY = 0

        # Whether the strategy can be applied to the provided URL.
        #
        # @param url [String] the URL to match against
        # @return [Boolean]
        sig { override.params(url: String).returns(T::Boolean) }
        def self.match?(url)
          GithubReleases.match?(url)
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

          match = url.delete_suffix(".git").match(GithubReleases::URL_MATCH_REGEX)
          return values if match.blank?

          values[:url] = "https://api.github.com/repos/#{match[:username]}/#{match[:repository]}/releases/latest"
          values[:username] = match[:username]
          values[:repository] = match[:repository]

          values
        end

        # Generates the GitHub API URL for the repository's "latest" release
        # and identifies the version from the JSON response.
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
        def self.find_versions(url:, regex: GithubReleases::DEFAULT_REGEX, options: Options.new, &block)
          match_data = { matches: {}, regex:, url: }

          generated = generate_input_values(url)
          return match_data if generated.blank?

          match_data[:url] = generated[:url]

          release = GitHub.get_latest_release(generated[:username], generated[:repository])
          GithubReleases.versions_from_content(release, regex, &block).each do |match_text|
            match_data[:matches][match_text] = Version.new(match_text)
          end

          match_data
        end
      end
    end
    GitHubLatest = Homebrew::Livecheck::Strategy::GithubLatest
  end
end
