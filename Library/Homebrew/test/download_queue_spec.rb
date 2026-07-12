# typed: true
# frozen_string_literal: true

require "download_queue"

RSpec.describe Homebrew::DownloadQueue do
  subject(:download_queue) { described_class.new }

  let(:cached_download) { HOMEBREW_CACHE/"downloads/testball--0.1.tar.gz" }
  let(:downloadable) do
    instance_double(
      Downloadable,
      cached_download:,
      checksum:               nil,
      downloaded_and_valid?:  false,
      downloader:             nil,
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

  it "skips fetching already downloaded files with a valid checksum" do
    cached_download.dirname.mkpath
    cached_download.write("already downloaded")

    allow(downloadable).to receive(:downloaded_and_valid?).and_return(true)

    expect(retryable_download).not_to receive(:fetch)
    expect(downloadable).to receive(:downloader).and_return(nil)

    download_queue.enqueue(downloadable)
    download_queue.fetch
  end

  it "runs queued staging before completing the fetch" do
    allow(retryable_download).to receive(:fetch).and_return(cached_download)

    expect(downloadable).to receive(:stage_from_download_queue?).with(cached_download, pour: false).and_return(true)
    expect(downloadable).to receive(:extracting!).ordered
    expect(downloadable).to receive(:stage_from_download_queue).with(cached_download, pour: false).ordered
    expect(downloadable).to receive(:downloaded!).ordered

    download_queue.enqueue(downloadable, stage: true)
    download_queue.fetch
  end

  it "checks attestations for valid cached bottles" do
    bottle = Bottle.allocate
    allow(bottle).to receive_messages(
      cached_download:,
      checksum:               nil,
      downloaded_and_valid?:  true,
      downloader:             nil,
      download_queue_message: "Bottle testball",
      download_queue_name:    "testball",
      download_queue_type:    "Bottle",
    )

    expect(Utils::Attestation).to receive(:check_attestation).with(bottle, quiet: true)

    download_queue.enqueue(bottle, check_attestation: true)
    download_queue.fetch
  end
end
