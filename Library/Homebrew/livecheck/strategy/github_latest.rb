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
        # @param server [String] the GitHub server base URL
        # @return [Boolean]
        # NOTE: `override` is required by the Sorbet runtime mixin (removing it raises
        # RuntimeError). The extra `server:` keyword has a default value, so the sig
        # remains compatible with the `Strategic` interface at both static and runtime levels.
        sig { override.params(url: String, server: String).returns(T::Boolean) }
        def self.match?(url, server: GithubReleases::GITHUB_SERVER_URL)
          GithubReleases.match?(url, server:)
        end

        # Extracts information from a provided URL and uses it to generate
        # various input values used by the strategy to check for new versions.
        # Some of these values act as defaults and can be overridden in a
        # `livecheck` block.
        #
        # @param url [String] the URL used to generate values
        # @param server [String] the GitHub server base URL
        # @return [Hash]
        sig { params(url: String, server: String).returns(T::Hash[Symbol, T.untyped]) }
        def self.generate_input_values(url, server: GithubReleases::GITHUB_SERVER_URL)
          values = {}
          server = server.sub(%r{/*$}, "")

          url_match_regex = if server == GithubReleases::GITHUB_SERVER_URL
            GithubReleases::URL_MATCH_REGEX
          else
            server_host = server.sub(%r{^https?://}, "")
            %r{
              ^https?://#{Regexp.escape(server_host)}
              /(?:downloads/)?(?<username>[^/]+) # The GitHub username
              /(?<repository>[^/]+)              # The GitHub repository name
            }ix
          end

          match = url.delete_suffix(".git").match(url_match_regex)
          return values if match.blank?

          api_url = (server == GithubReleases::GITHUB_SERVER_URL) ? GitHub::API_URL : "#{server}/api/v3"
          values[:url] = "#{api_url}/repos/#{match[:username]}/#{match[:repository]}/releases/latest"
          values[:username] = match[:username]
          values[:repository] = match[:repository]

          values
        end

        # Generates the GitHub API URL for the repository's "latest" release
        # and identifies the version from the JSON response.
        #
        # @param url [String] the URL of the content to check
        # @param regex [Regexp] a regex for matching versions in content
        # @param content [Hash, nil] content to check instead of fetching
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
          regex ||= GithubReleases::DEFAULT_REGEX
          match_data = { matches: {}, regex:, url: }
          match_data[:cached] = true if content

          server = options.github_server_url.presence || GithubReleases::GITHUB_SERVER_URL
          generated = generate_input_values(url, server:)
          return match_data if generated.blank?

          match_data[:url] = generated[:url]

          unless match_data[:cached]
            match_data[:content] = GitHub::API.open_rest(generated[:url], parse_json: false)
            content = match_data[:content]
          end
          return match_data if content.blank?

          GithubReleases.versions_from_content(content, regex, &block).each do |match_text|
            match_data[:matches][match_text] = Version.new(match_text)
          end

          match_data
        end
      end
    end
    GitHubLatest = Homebrew::Livecheck::Strategy::GithubLatest
  end
end
