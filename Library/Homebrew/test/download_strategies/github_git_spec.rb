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
end
