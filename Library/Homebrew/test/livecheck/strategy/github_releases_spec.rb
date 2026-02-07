# frozen_string_literal: true

require "livecheck/strategy"

RSpec.describe Homebrew::Livecheck::Strategy::GithubReleases do
  subject(:github_releases) { described_class }

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

  let(:regex) { github_releases::DEFAULT_REGEX }

  let(:generated) do
    {
      def:  {
        url:        "https://api.github.com/repos/abc/def/releases",
        username:   "abc",
        repository: "def",
      },
      brew: {
        url:        "https://api.github.com/repos/Homebrew/brew/releases",
        username:   "Homebrew",
        repository: "brew",
      },
    }
  end

  # For the sake of brevity, this is a limited subset of the information found
  # in release objects in a response from the GitHub API. Some of these objects
  # are somewhat representative of real world scenarios but others are
  # contrived examples for the sake of exercising code paths.
  let(:content) do
    <<~EOS
      [
        {
          "tag_name": "v1.2.3",
          "name": "v1.2.3",
          "draft": false,
          "prerelease": false
        },
        {
          "tag_name": "no-version-tag-also",
          "name": "1.2.2",
          "draft": false,
          "prerelease": false
        },
        {
          "tag_name": "1.2.1",
          "name": "No version title",
          "draft": false,
          "prerelease": false
        },
        {
          "tag_name": "no-version-tag",
          "name": "No version title",
          "draft": false,
          "prerelease": false
        },
        {
          "tag_name": "v1.1.2",
          "name": "v1.1.2",
          "draft": false,
          "prerelease": true
        },
        {
          "tag_name": "v1.1.1",
          "name": "v1.1.1",
          "draft": true,
          "prerelease": false
        },
        {
          "tag_name": "v1.1.0",
          "name": "v1.1.0",
          "draft": true,
          "prerelease": true
        },
        {
          "other": "something-else"
        }
      ]
    EOS
  end
  let(:json) { JSON.parse(content) }

  let(:matches) { ["1.2.3", "1.2.2", "1.2.1"] }

  describe "::match?" do
    it "returns true for a GitHub release artifact URL" do
      expect(github_releases.match?(github_urls[:release_asset])).to be true
    end

    it "returns true for a GitHub tag archive URL" do
      expect(github_releases.match?(github_urls[:short_tag_archive])).to be true
      expect(github_releases.match?(github_urls[:long_tag_archive])).to be true
    end

    it "returns true for a GitHub repository upload URL" do
      expect(github_releases.match?(github_urls[:repository_upload])).to be true
    end

    it "returns false for a non-GitHub URL" do
      expect(github_releases.match?(non_github_url)).to be false
    end
  end

  describe "::generate_input_values" do
    it "returns a hash containing a url and regex for a GitHub release artifact URL" do
      expect(github_releases.generate_input_values(github_urls[:release_asset])).to eq(generated[:def])
    end

    it "returns a hash containing a url and regex for a GitHub tag archive URL" do
      expect(github_releases.generate_input_values(github_urls[:short_tag_archive])).to eq(generated[:def])
      expect(github_releases.generate_input_values(github_urls[:long_tag_archive])).to eq(generated[:def])
    end

    it "returns a hash containing a url and regex for a GitHub repository upload URL" do
      expect(github_releases.generate_input_values(github_urls[:repository_upload])).to eq(generated[:def])
    end

    it "returns an empty hash for a non-GitHub URL" do
      expect(github_releases.generate_input_values(non_github_url)).to eq({})
    end
  end

  describe "::versions_from_content" do
    it "returns an empty array if content is blank" do
      expect(github_releases.versions_from_content("", regex)).to eq([])
      expect(github_releases.versions_from_content("[]", regex)).to eq([])
    end

    it "returns an array of version strings when given content" do
      expect(github_releases.versions_from_content(content, regex)).to eq(matches)
    end

    it "returns an array of version strings when given content and a block" do
      # Returning a string from block
      expect(github_releases.versions_from_content(content, regex) { "1.2.3" }).to eq(["1.2.3"])

      # Returning an array of strings from block
      expect(github_releases.versions_from_content(content, regex) do |json, regex|
        json.map do |release|
          next if release["draft"] || release["prerelease"]

          match = release["tag_name"]&.match(regex)
          next if match.blank?

          match[1]
        end
      end).to eq(["1.2.3", "1.2.1"])
    end

    it "allows a nil return from a block" do
      expect(github_releases.versions_from_content(content, regex) { next }).to eq([])
    end

    it "errors on an invalid return type from a block" do
      expect { github_releases.versions_from_content(content, regex) { 123 } }
        .to raise_error(TypeError, Homebrew::Livecheck::Strategy::INVALID_BLOCK_RETURN_VALUE_MSG)
    end
  end

  describe "::find_versions" do
    let(:match_data) do
      base = {
        matches: matches.to_h { |v| [v, Version.new(v)] },
        regex:,
        url:     generated[:brew][:url],
      }

      {
        fetched:        base.merge({ content: }),
        cached:         base.merge({ cached: true }),
        cached_default: base.merge({ matches: {}, cached: true }),
      }
    end

    let(:brew_regex) { /^v?(\d+(?:\.\d+)+)$/i }

    it "finds versions in fetched content" do
      allow(GitHub::API).to receive(:open_rest).and_return(content)

      expect(github_releases.find_versions(url: github_urls[:brew_tag_archive]))
        .to eq(match_data[:fetched])
    end

    it "finds versions in provided content" do
      expect(github_releases.find_versions(url: github_urls[:brew_tag_archive], content:))
        .to eq(match_data[:cached])

      # This `strategy` block is unnecessary but it's intended to test using a
      # regex in a `strategy` block.
      expect(
        github_releases.find_versions(
          url:     github_urls[:brew_tag_archive],
          regex:   brew_regex,
          content:,
        ) do |json, regex|
          json.map do |release|
            next if release["draft"] || release["prerelease"]

            match = release["tag_name"]&.match(regex)
            next if match.blank?

            match[1]
          end
        end,
      ).to eq(match_data[:cached].merge({
        matches: ["1.2.3", "1.2.1"].to_h { |v| [v, Version.new(v)] },
        regex:   brew_regex,
      }))
    end

    it "returns default match_data when url is blank" do
      expect(github_releases.find_versions(url: ""))
        .to eq({ matches: {}, regex: github_releases::DEFAULT_REGEX, url: "" })
    end

    it "returns default match_data when content is blank" do
      expect(github_releases.find_versions(url: github_urls[:brew_tag_archive], content: ""))
        .to eq(match_data[:cached_default])
    end
  end
end
