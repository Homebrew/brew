# typed: true
# frozen_string_literal: true

require "download_queue"

RSpec.describe Homebrew::DownloadQueue do
  subject(:download_queue) { klass.new }

  let(:klass) { Homebrew::DownloadQueue }
  let(:cached_download) { HOMEBREW_CACHE/"downloads/testball--0.1.tar.gz" }
  let(:downloadable) do
    instance_double(
      Downloadable,
      cached_download:,
      download_queue_message: "Bottle testball",
      download_queue_name:    "testball",
      download_queue_type:    "Bottle",
    )
  end
  let(:download_error) { DownloadError.new(downloadable, RuntimeError.new("network blew up")) }
  let(:retryable_download) { instance_double(Homebrew::RetryableDownload) }

  before do
    allow(Homebrew::EnvConfig).to receive(:download_concurrency).and_return(2)
    allow(retryable_download).to receive(:fetch).and_raise(download_error)
    allow(Homebrew::RetryableDownload).to receive(:new).and_return(retryable_download)
  end

  after do
    download_queue.shutdown
  end

  it "reports rejected download errors in parallel mode and marks the fetch as failed" do
    download_queue.enqueue(downloadable)

    expect { download_queue.fetch }.to output(/network blew up/).to_stderr

    expect(download_queue.fetch_failed).to be(true)
    expect(Homebrew).to have_failed
  end
end
