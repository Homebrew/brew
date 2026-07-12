# typed: strict
# frozen_string_literal: true

require "bottle"
require "api/json_download"
require "utils/output"

module Homebrew
  class RetryableDownload
    include Downloadable
    include Utils::Output::Mixin

    sig { override.returns(T.nilable(T.any(String, URL))) }
    def url = downloadable.url

    sig { override.returns(T.nilable(Checksum)) }
    def checksum = downloadable.checksum

    sig { override.returns(T::Array[String]) }
    def mirrors = downloadable.mirrors

    sig { params(downloadable: Downloadable, tries: Integer).void }
    def initialize(downloadable, tries:)
      super()

      @downloadable = downloadable
      @try = T.let(0, Integer)
      @tries = tries
    end

    sig { override.returns(String) }
    def download_queue_name = downloadable.download_queue_name

    sig { override.returns(String) }
    def download_queue_type = downloadable.download_queue_type

    sig { override.returns(Pathname) }
    def cached_download = downloadable.cached_download

    sig { override.void }
    def clear_cache = downloadable.clear_cache

    sig { override.returns(T.nilable(Version)) }
    def version = downloadable.version

    sig { override.returns(T::Class[AbstractDownloadStrategy]) }
    def download_strategy = downloadable.download_strategy

    sig { override.returns(AbstractDownloadStrategy) }
    def downloader = downloadable.downloader

    sig {
      override.params(
        verify_download_integrity: T::Boolean,
        timeout:                   T.nilable(T.any(Integer, Float)),
        quiet:                     T::Boolean,
      ).returns(Pathname)
    }
    def fetch(verify_download_integrity: true, timeout: nil, quiet: false)
      @try += 1

      downloadable.downloading!

      already_downloaded = downloadable.downloaded?

      download = if downloadable.is_a?(Resource) && (resource = T.cast(downloadable, Resource))
        resource.fetch(verify_download_integrity: false, timeout:, quiet:, skip_patches: true)
      else
        downloadable.fetch(verify_download_integrity: false, timeout:, quiet:)
      end

      downloadable.downloaded!

      return download unless download.file?

      unless quiet
        puts "Downloaded to: #{download}" unless already_downloaded
        puts "SHA-256: #{download.sha256}"
      end

      json_download = downloadable.is_a?(API::JSONDownload)
      downloadable.verify_download_integrity(download) if verify_download_integrity && !json_download

      FileUtils.touch(download, mtime: Time.now) if json_download

      download
    rescue DownloadError, ChecksumMismatchError, Resource::BottleManifest::Error => e
      tries_remaining = @tries - @try
      raise if tries_remaining.zero?

      wait = 2 ** @try
      unless quiet
        what = Utils.pluralize("try", tries_remaining)
        ohai "Retrying download in #{wait}s... (#{tries_remaining} #{what} left)"
      end
      sleep wait

      # Preserve the partial `.incomplete` file on network errors so the next
      # attempt can resume via `--continue-at`. Clear the cache only when the
      # fully-downloaded file is known-bad (checksum or manifest mismatch).
      downloadable.clear_cache unless e.is_a?(DownloadError)
      retry
    end

    sig { override.params(filename: Pathname).void }
    def verify_download_integrity(filename) = downloadable.verify_download_integrity(filename)

    private

    sig { returns(Downloadable) }
    attr_reader :downloadable
  end
end
