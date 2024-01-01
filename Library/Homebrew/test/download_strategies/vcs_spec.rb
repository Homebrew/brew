# frozen_string_literal: true

require "download_strategy"

describe VCSDownloadStrategy do
  let(:url) { "https://example.com/bar" }
  let(:version) { nil }

  describe "#cached_location" do
    it "returns the path of the cached resource" do
      allow_any_instance_of(described_class).to receive(:cache_tag).and_return("foo")
      downloader = described_class.new(url, "baz", version)
      expect(downloader.cached_location).to eq(HOMEBREW_CACHE/"baz--foo")
    end
  end
end
