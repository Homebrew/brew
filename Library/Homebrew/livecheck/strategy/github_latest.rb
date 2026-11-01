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
      # "latest" release for a suitable version and {Git} can't adequately
      # identify the latest version (e.g. tags using a stable version format are
      # marked as pre-release, not every tag receives a release, etc.) or
      # there's a notable time gap between a tag and release. The strategy can
      # only be applied by using `strategy :github_latest` in a `livecheck`
      # block.
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

        # A priority of zero causes livecheck to skip the strategy. We do this
        # for {GithubLatest} so we can selectively apply the strategy using
        # `strategy :github_latest` in a `livecheck` block.
        PRIORITY = 0

        # A GraphQL query to fetch a repository's "latest" release tag, which
        # can be used for basic checks without a `strategy` block.
        LATEST_RELEASE_TAG_QUERY = <<~GRAPHQL
          query($owner: String!, $name: String!) {
            repository(owner: $owner, name: $name) {
              latestRelease { tagName }
            }
          }
        GRAPHQL

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
        # @param use_rest whether to generate a REST API URL
        # @return [Hash]
        sig { params(url: String, use_rest: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
        def self.generate_input_values(url, use_rest: true)
          values = {}

          match = url.delete_suffix(".git").match(GithubReleases::URL_MATCH_REGEX)
          return values if match.blank?

          values[:url] = if use_rest
            "#{GitHub::API_URL}/repos/#{match[:username]}/#{match[:repository]}/releases/latest"
          else
            "#{GitHub::API_URL}/graphql"
          end
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

          use_rest = block_given? || GitHub::API.credentials_type == :none
          generated = generate_input_values(url, use_rest:)
          return match_data if generated.blank?

          match_data[:url] = generated[:url]

          unless match_data[:cached]
            match_data[:content] = if use_rest
              GitHub::API.open_rest(generated[:url], parse_json: false)
            else
              # Use the GraphQL API to fetch minimal data and structure the JSON
              # to match REST API responses
              tag_name = GitHub::API.open_graphql(
                LATEST_RELEASE_TAG_QUERY,
                variables: {
                  owner: generated[:username],
                  name:  generated[:repository],
                },
              )&.dig("repository", "latestRelease", "tagName")
              "#{JSON.pretty_generate({ tag_name: })}\n" if tag_name
            end
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
  end
end
