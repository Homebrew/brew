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

        # A GraphQL query to fetch a repository's recent release tags and their
        # draft/pre-release status, which can be used for basic checks without
        # a `strategy` block. This is intended to align with the REST API's
        # pagination behaviour.
        RELEASE_TAGS_QUERY = <<~GRAPHQL
          query($owner: String!, $name: String!) {
            repository(owner: $owner, name: $name) {
              releases(first: 30, orderBy: { field: CREATED_AT, direction: DESC }) {
                nodes { tagName isDraft isPrerelease }
              }
            }
          }
        GRAPHQL

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
        # @param fetch_type the type of GitHub data to fetch
        # @return [Hash]
        sig { params(url: String, fetch_type: Symbol).returns(T::Hash[Symbol, T.untyped]) }
        def self.generate_input_values(url, fetch_type: :rest_api)
          values = {}

          match = url.delete_suffix(".git").match(URL_MATCH_REGEX)
          return values if match.blank?

          values[:url] = case fetch_type
          when :graphql_api
            "#{GitHub::API_URL}/graphql"
          when :rest_api
            "#{GitHub::API_URL}/repos/#{match[:username]}/#{match[:repository]}/releases"
          else
            raise ArgumentError, "Unrecognized `fetch_type` argument"
          end
          values[:username] = match[:username]
          values[:repository] = match[:repository]

          values
        end

        # Uses a regex to match versions from release JSON or, if a block is
        # provided, passes the JSON to the block to handle matching. With
        # either approach, an array of unique matches is returned.
        #
        # @param content [Array, Hash] an array of releases or a single release
        # @param regex [Regexp] a regex for matching versions in content
        # @return [Array]
        sig {
          params(
            content: String,
            regex:   Regexp,
            block:   T.nilable(Proc),
          ).returns(T::Array[String])
        }
        def self.versions_from_content(content, regex, &block)
          return [] if content.blank?

          json = Json.parse_json(content)
          return [] if json.blank?

          if block.present?
            block_return_value = yield(json, regex)
            return Strategy.handle_block_return(block_return_value)
          end

          json = [json] unless json.is_a?(Array)
          json.compact_blank.filter_map do |release|
            next if release["draft"] || release["prerelease"]

            release["tag_name"]&.[](regex, 1)
          end.uniq
        end

        # Generates the GitHub API URL for the repository's recent releases
        # and identifies versions from the JSON response.
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
          regex ||= DEFAULT_REGEX
          match_data = { matches: {}, regex:, url: }
          match_data[:cached] = true if content

          fetch_type =
            if !block_given? && Homebrew::EnvConfig.livecheck_use_github_graphql?
              :graphql_api
            else
              :rest_api
            end
          generated = generate_input_values(url, fetch_type:)
          return match_data if generated.blank?

          match_data[:url] = generated[:url]

          unless match_data[:cached]
            if Homebrew::EnvConfig.no_github_api?
              raise "#{Utils.demodulize(name)} cannot be used when `HOMEBREW_NO_GITHUB_API` is set"
            end

            match_data[:content] = if fetch_type == :graphql_api
              # Use the GraphQL API to fetch minimal data and structure the JSON
              # to match REST API responses
              releases = GitHub::API.open_graphql(
                RELEASE_TAGS_QUERY,
                variables: {
                  owner: generated[:username],
                  name:  generated[:repository],
                },
              )&.dig("repository", "releases", "nodes")
              if releases.present?
                rest_releases = releases.compact.map do |release|
                  {
                    tag_name:   release["tagName"],
                    draft:      release["isDraft"],
                    prerelease: release["isPrerelease"],
                  }
                end
                "#{JSON.pretty_generate(rest_releases)}\n"
              end
            else
              GitHub::API.open_rest(generated[:url], parse_json: false)
            end
            content = match_data[:content]
          end
          return match_data if content.blank?

          versions_from_content(content, regex, &block).each do |match_text|
            match_data[:matches][match_text] = Version.new(match_text)
          end

          match_data
        end
      end
    end
    GitHubReleases = Homebrew::Livecheck::Strategy::GithubReleases
  end
end
