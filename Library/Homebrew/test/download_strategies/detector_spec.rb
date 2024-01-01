# frozen_string_literal: true

require "download_strategy"

describe DownloadStrategyDetector do
  describe "::detect" do
    subject(:strategy_detector) { described_class.detect(url, strategy) }

    let(:url) { Object.new }
    let(:strategy) { nil }

    context "when given Git URL" do
      let(:url) { "git://example.com/foo.git" }

      it { is_expected.to eq(GitDownloadStrategy) }
    end

    context "when given a GitHub Git URL" do
      let(:url) { "https://github.com/homebrew/brew.git" }

      it { is_expected.to eq(GitHubGitDownloadStrategy) }
    end

    it "defaults to curl" do
      expect(strategy_detector).to eq(CurlDownloadStrategy)
    end

    it "raises an error when passed an unrecognized strategy" do
      expect do
        described_class.detect("foo", Class.new)
      end.to raise_error(TypeError)
    end
  end
end
