# typed: true
# frozen_string_literal: true

require "livecheck/strategy"

RSpec.describe Homebrew::Livecheck::Strategy::GithubLatest do
  subject(:github_latest) { described_class }

  let(:github_urls) do
    {
      release_asset:     "https://github.com/abc/def/releases/download/1.2.3/ghi-1.2.3.tar.gz",
      short_tag_archive: "https://github.com/abc/def/archive/v1.2.3.tar.gz",
      long_tag_archive:  "https://github.com/abc/def/archive/refs/tags/1.2.3.tar.gz",
      repository_upload: "https://github.com/downloads/abc/def/ghi-1.2.3.tar.gz",
      brew_tag_archive:  "https://github.com/Homebrew/brew/archive/1.2.3.tar.gz",
    }
  end
  let(:non_github_url) { "https://brew.sh/test" }
  let(:generated) do
    data = {
      def_rest:  {
        url:        "https://api.github.com/repos/abc/def/releases/latest",
        username:   "abc",
        repository: "def",
      },
      brew_rest: {
        url:        "https://api.github.com/repos/Homebrew/brew/releases/latest",
        username:   "Homebrew",
        repository: "brew",
      },
    }

    graphql_url = "https://api.github.com/graphql"
    data[:def_graphql] = data[:def_rest].merge({ url: graphql_url })
    data[:brew_graphql] = data[:brew_rest].merge({ url: graphql_url })
    data
  end
  # For the sake of brevity, this is a limited subset of the information found
  # in release objects in a response from the GitHub API.
  let(:content) do
    <<~JSON
      {
        "tag_name": "1.2.3"
      }
    JSON
  end
  let(:matches) { ["1.2.3"] }

  describe "::match?" do
    it "returns true for a GitHub release artifact URL" do
      expect(github_latest.match?(github_urls[:release_asset])).to be true
    end

    it "returns true for a GitHub tag archive URL" do
      expect(github_latest.match?(github_urls[:short_tag_archive])).to be true
      expect(github_latest.match?(github_urls[:long_tag_archive])).to be true
    end

    it "returns true for a GitHub repository upload URL" do
      expect(github_latest.match?(github_urls[:repository_upload])).to be true
    end

    it "returns false for a non-GitHub URL" do
      expect(github_latest.match?(non_github_url)).to be false
    end
  end

  describe "::generate_input_values" do
    it "returns a hash containing a url and regex for a GitHub release artifact URL" do
      expect(github_latest.generate_input_values(github_urls[:release_asset])).to eq(generated[:def_rest])
    end

    it "returns a hash containing a url and regex for a GitHub tag archive URL" do
      expect(github_latest.generate_input_values(github_urls[:short_tag_archive])).to eq(generated[:def_rest])
      expect(github_latest.generate_input_values(github_urls[:long_tag_archive])).to eq(generated[:def_rest])
    end

    it "returns a hash containing a url and regex for a GitHub repository upload URL" do
      expect(github_latest.generate_input_values(github_urls[:repository_upload])).to eq(generated[:def_rest])
    end

    it "returns a hash containing a REST API url when it should be used" do
      expect(github_latest.generate_input_values(github_urls[:release_asset], use_rest: true))
        .to eq(generated[:def_rest])
    end

    it "returns a hash containing a GraphQL API url when REST should not be used" do
      expect(github_latest.generate_input_values(github_urls[:release_asset], use_rest: false))
        .to eq(generated[:def_graphql])
    end

    it "returns an empty hash for a non-GitHub URL" do
      expect(github_latest.generate_input_values(non_github_url)).to eq({})
    end
  end

  describe "::find_versions" do
    let(:match_data) do
      base = {
        matches: matches.to_h { |v| [v, Version.new(v)] },
        regex:   Homebrew::Livecheck::Strategy::GithubReleases::DEFAULT_REGEX,
        url:     generated[:brew_rest][:url],
      }

      {
        fetched_rest:    base.merge({ content: }),
        fetched_graphql: base.merge({
          url:     generated[:brew_graphql][:url],
          content:,
        }),
        cached:          base.merge({ cached: true }),
        cached_default:  base.merge({ matches: {}, cached: true }),
      }
    end

    let(:brew_regex) { /^v?(\d+(?:\.\d+)+)$/i }

    it "finds versions in content fetched from the REST API" do
      allow(GitHub::API).to receive_messages(credentials_type: :none, open_rest: content)

      expect(github_latest.find_versions(url: github_urls[:brew_tag_archive]))
        .to eq(match_data[:fetched_rest])
    end

    it "uses the REST API when a `strategy` block is provided" do
      allow(GitHub::API).to receive_messages(credentials_type: :env_token, open_rest: content)

      expect(github_latest.find_versions(url: github_urls[:brew_tag_archive]) { |json| json["tag_name"] })
        .to eq(match_data[:fetched_rest])
    end

    it "finds versions in content fetched from the GraphQL API" do
      allow(GitHub::API).to receive_messages(
        credentials_type: :env_token,
        open_graphql:     {
          "repository" => { "latestRelease" => { "tagName" => "1.2.3" } },
        },
      )

      expect(github_latest.find_versions(url: github_urls[:brew_tag_archive]))
        .to eq(match_data[:fetched_graphql])
    end

    it "returns no matches from the GraphQL API when the repository has no latest release" do
      allow(GitHub::API).to receive_messages(
        credentials_type: :env_token,
        open_graphql:     { "repository" => { "latestRelease" => nil } },
      )

      expect(github_latest.find_versions(url: github_urls[:brew_tag_archive]))
        .to eq(match_data[:fetched_graphql].merge({ matches: {}, content: nil }))
    end

    it "returns no matches from the GraphQL API when there is no content" do
      allow(GitHub::API).to receive_messages(
        credentials_type: :env_token,
        open_graphql:     nil,
      )

      expect(github_latest.find_versions(url: github_urls[:brew_tag_archive]))
        .to eq(match_data[:fetched_graphql].merge({ matches: {}, content: nil }))
    end

    it "finds versions in provided content" do
      allow(GitHub::API).to receive(:credentials_type).and_return(:none)

      expect(github_latest.find_versions(url: github_urls[:brew_tag_archive], content:))
        .to eq(match_data[:cached])

      # This `strategy` block is unnecessary but it's intended to test using a
      # regex in a `strategy` block.
      expect(
        github_latest.find_versions(
          url:     github_urls[:brew_tag_archive],
          regex:   brew_regex,
          content:,
        ) do |json, regex|
          match = json["tag_name"]&.match(regex)
          next if match.blank?

          match[1]
        end,
      ).to eq(match_data[:cached].merge({ regex: brew_regex }))
    end

    it "returns default match_data when url is blank" do
      expect(github_latest.find_versions(url: ""))
        .to eq({ matches: {}, regex: Homebrew::Livecheck::Strategy::GithubReleases::DEFAULT_REGEX, url: "" })
    end

    it "returns default match_data when content is blank" do
      allow(GitHub::API).to receive(:credentials_type).and_return(:none)

      expect(github_latest.find_versions(url: github_urls[:brew_tag_archive], content: ""))
        .to eq(match_data[:cached_default])
    end
  end
end
