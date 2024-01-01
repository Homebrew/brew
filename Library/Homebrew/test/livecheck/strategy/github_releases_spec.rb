# frozen_string_literal: true

require "livecheck/strategy"

describe Homebrew::Livecheck::Strategy::GithubReleases do
  subject(:github_releases) { described_class }

  let(:github_urls) do
    {
      release_artifact:  "https://github.com/abc/def/releases/download/1.2.3/ghi-1.2.3.tar.gz",
      tag_archive:       "https://github.com/abc/def/archive/v1.2.3.tar.gz",
      repository_upload: "https://github.com/downloads/abc/def/ghi-1.2.3.tar.gz",
    }
  end
  let(:non_github_url) { "https://brew.sh/test" }

  let(:regex) { github_releases::DEFAULT_REGEX }

  let(:generated) do
    {
      url:        "https://api.github.com/repos/abc/def/releases",
      username:   "abc",
      repository: "def",
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
      expect(github_releases.match?(github_urls[:release_artifact])).to be true
    end

    it "returns true for a GitHub tag archive URL" do
      expect(github_releases.match?(github_urls[:tag_archive])).to be true
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
      expect(github_releases.generate_input_values(github_urls[:release_artifact])).to eq(generated)
    end

    it "returns a hash containing a url and regex for a GitHub tag archive URL" do
      expect(github_releases.generate_input_values(github_urls[:tag_archive])).to eq(generated)
    end

    it "returns a hash containing a url and regex for a GitHub repository upload URL" do
      expect(github_releases.generate_input_values(github_urls[:repository_upload])).to eq(generated)
    end

    it "returns an empty hash for a non-Github URL" do
      expect(github_releases.generate_input_values(non_github_url)).to eq({})
    end
  end

  describe "::versions_from_content" do
    it "returns an empty array if content is blank" do
      expect(github_releases.versions_from_content({}, regex)).to eq([])
    end

    it "returns an array of version strings when given content" do
      expect(github_releases.versions_from_content(json, regex)).to eq(matches)
    end

    it "returns an array of version strings when given content and a block" do
      # Returning a string from block
      expect(github_releases.versions_from_content(json, regex) { "1.2.3" }).to eq(["1.2.3"])

      # Returning an array of strings from block
      expect(github_releases.versions_from_content(json, regex) do |json, regex|
        json.map do |release|
          next if release["draft"] || release["prerelease"]

          match = release["tag_name"]&.match(regex)
          next if match.blank?

          match[1]
        end
      end).to eq(["1.2.3", "1.2.1"])
    end

    it "allows a nil return from a block" do
      expect(github_releases.versions_from_content(json, regex) { next }).to eq([])
    end

    it "errors on an invalid return type from a block" do
      expect { github_releases.versions_from_content(json, regex) { 123 } }
        .to raise_error(TypeError, Homebrew::Livecheck::Strategy::INVALID_BLOCK_RETURN_VALUE_MSG)
    end
  end
end
