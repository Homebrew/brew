# frozen_string_literal: true

require "livecheck/strategy/github_releases"
require "livecheck/strategy/github_latest"

describe Homebrew::Livecheck::Strategy::GithubLatest do
  subject(:github_latest) { described_class }

  let(:github_urls) do
    {
      release_artifact:  "https://github.com/abc/def/releases/download/1.2.3/ghi-1.2.3.tar.gz",
      tag_archive:       "https://github.com/abc/def/archive/v1.2.3.tar.gz",
      repository_upload: "https://github.com/downloads/abc/def/ghi-1.2.3.tar.gz",
    }
  end
  let(:non_github_url) { "https://brew.sh/test" }

  let(:generated) do
    {
      url:        "https://api.github.com/repos/abc/def/releases/latest",
      username:   "abc",
      repository: "def",
    }
  end

  describe "::match?" do
    it "returns true for a GitHub release artifact URL" do
      expect(github_latest.match?(github_urls[:release_artifact])).to be true
    end

    it "returns true for a GitHub tag archive URL" do
      expect(github_latest.match?(github_urls[:tag_archive])).to be true
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
      expect(github_latest.generate_input_values(github_urls[:release_artifact])).to eq(generated)
    end

    it "returns a hash containing a url and regex for a GitHub tag archive URL" do
      expect(github_latest.generate_input_values(github_urls[:tag_archive])).to eq(generated)
    end

    it "returns a hash containing a url and regex for a GitHub repository upload URL" do
      expect(github_latest.generate_input_values(github_urls[:repository_upload])).to eq(generated)
    end

    it "returns an empty hash for a non-Github URL" do
      expect(github_latest.generate_input_values(non_github_url)).to eq({})
    end
  end
end
