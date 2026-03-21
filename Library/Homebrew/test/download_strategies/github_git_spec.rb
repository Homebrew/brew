# frozen_string_literal: true

require "download_strategy"

RSpec.describe GitHubGitDownloadStrategy do
  subject(:strategy) { described_class.new(url, name, version) }

  let(:name) { "brew" }
  let(:url) { "https://github.com/homebrew/brew.git" }
  let(:version) { nil }

  it "parses the URL and sets the corresponding instance variables" do
    expect(strategy.instance_variable_get(:@user)).to eq("homebrew")
    expect(strategy.instance_variable_get(:@repo)).to eq("brew")
    expect(strategy.instance_variable_get(:@github_server_url)).to eq("https://github.com")
  end

  context "with a custom GitHub server URL" do
    subject(:strategy) do
      described_class.new(url, name, version, github_server_url: "https://github.example.com")
    end

    let(:url) { "https://github.example.com/homebrew/brew.git" }

    it "parses the custom server URL and sets the corresponding instance variables" do
      expect(strategy.instance_variable_get(:@user)).to eq("homebrew")
      expect(strategy.instance_variable_get(:@repo)).to eq("brew")
      expect(strategy.instance_variable_get(:@github_server_url)).to eq("https://github.example.com")
    end

    it "auto-detects the server URL from the URL when github_server_url is not provided" do
      auto = described_class.new(url, name, version)
      expect(auto.instance_variable_get(:@github_server_url)).to eq("https://github.example.com")
      expect(auto.instance_variable_get(:@user)).to eq("homebrew")
      expect(auto.instance_variable_get(:@repo)).to eq("brew")
    end

    it "strips a trailing slash from the provided github_server_url" do
      trailing = described_class.new(url, name, version, github_server_url: "https://github.example.com/")
      expect(trailing.instance_variable_get(:@github_server_url)).to eq("https://github.example.com")
    end

    it "does not set user and repo for a mismatched URL" do
      mismatched = described_class.new("https://github.com/homebrew/brew.git", name, version,
                                       github_server_url: "https://github.example.com")
      expect(mismatched.instance_variable_get(:@user)).to be_nil
      expect(mismatched.instance_variable_get(:@repo)).to be_nil
    end

    it "falls back to superclass last_commit for a mismatched URL" do
      mismatched = described_class.new("https://github.com/homebrew/brew.git", name, version,
                                       github_server_url: "https://github.example.com")
      expect(GitHub).not_to receive(:last_commit)
      expect(mismatched.last_commit).to eq("")
    end

    it "falls back to superclass commit_outdated? for a mismatched URL" do
      mismatched = described_class.new("https://github.com/homebrew/brew.git", name, version,
                                       github_server_url: "https://github.example.com")
      allow(mismatched).to receive(:fetch_last_commit).and_return("abc123def456")
      expect(GitHub).not_to receive(:last_commit)
      expect(GitHub).not_to receive(:multiple_short_commits_exist?)
      expect(mismatched.commit_outdated?("abc123")).to be true
    end
  end
end
