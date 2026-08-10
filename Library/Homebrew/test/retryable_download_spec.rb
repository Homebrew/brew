# typed: true
# frozen_string_literal: true

require "retryable_download"

RSpec.describe Homebrew::RetryableDownload do
  it "preserves the response mtime for API JSON downloads" do
    target = mktmpdir/"api.json"
    response_mtime = Time.now - 3600
    target.write "{}"
    FileUtils.touch(target, mtime: response_mtime)

    download = Homebrew::API::JSONDownload.new("api.json", target:, stale_seconds: 3600)
    allow(download).to receive(:fetch).and_return(target)

    described_class.new(download, tries: 1).fetch(quiet: true)

    expect(target.mtime.to_i).to eq(response_mtime.to_i)
  end
end
