# typed: true
# frozen_string_literal: true

require "download_strategy"

RSpec.describe GitHubGitDownloadStrategy do
  subject(:strategy) { described_class.new(url, name, version) }

  let(:name) { "brew" }
  let(:url) { "https://github.com/homebrew/brew.git" }
  let(:version) { nil }

  it "parses the URL and sets the corresponding instance variables" do
    expect(strategy.user).to eq("homebrew")
    expect(strategy.repo).to eq("brew")
  end

  describe "#commit_outdated?" do
    let(:version) { Version.new("HEAD") }
    let(:cached_location) { strategy.cached_location }

    it "fetches the repository if the GitHub API is unavailable" do
      allow(GitHub).to receive_messages(last_commit: nil, multiple_short_commits_exist?: false)
      expect(strategy).to receive(:fetch_last_commit).and_return("f68266e")

      cached_location.mkpath
      cached_location.cd do
        system "git", "-c", "init.defaultBranch=master", "init"
        FileUtils.touch "README"
        system "git", "add", "--all"
        system "git", "commit", "-m", "stale commit"
      end
      stale_commit = Utils.popen_read("git", "-C", cached_location, "rev-parse", "--short=7", "HEAD").chomp

      expect(strategy.commit_outdated?(stale_commit)).to be true
    end
  end
end
