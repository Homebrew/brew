# typed: strict
# frozen_string_literal: true

require "bottle"
require "api/json_download"

module Homebrew
  class RetryableDownload
    include Downloadable

    sig { override.returns(T.any(NilClass, String, URL)) }
    def url = downloadable.url

    sig { override.returns(T.nilable(Checksum)) }
    def checksum = downloadable.checksum

    sig { override.returns(T::Array[String]) }
    def mirrors = downloadable.mirrors

    sig { params(downloadable: Downloadable, tries: Integer, pour: T::Boolean).void }
    def initialize(downloadable, tries:, pour: false)
      super()

      @downloadable = downloadable
      @try = T.let(0, Integer)
      @tries = tries
      @pour = pour
    end

    sig { override.returns(String) }
    def name = downloadable.name

    sig { override.returns(String) }
    def download_type = downloadable.download_type

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

      already_downloaded = downloadable.downloaded?

      download = downloadable.fetch(verify_download_integrity: false, timeout:, quiet:)

      return download unless download.file?

      unless quiet
        puts "Downloaded to: #{download}" unless already_downloaded
        puts "SHA256: #{download.sha256}"
      end

      json_download = downloadable.is_a?(API::JSONDownload)
      downloadable.verify_download_integrity(download) if verify_download_integrity && !json_download

      if pour && downloadable.is_a?(Bottle)
        HOMEBREW_CELLAR.mkpath
        UnpackStrategy.detect(download, prioritize_extension: true)
                      .extract_nestedly(to: HOMEBREW_CELLAR)
      elsif json_download
        FileUtils.touch(download, mtime: Time.now)
      end

      download
    rescue DownloadError, ChecksumMismatchError, Resource::BottleManifest::Error
      tries_remaining = @tries - @try
      raise if tries_remaining.zero?

      wait = 2 ** @try
      unless quiet
        what = Utils.pluralize("tr", tries_remaining, plural: "ies", singular: "y")
        ohai "Retrying download in #{wait}s... (#{tries_remaining} #{what} left)"
      end
      sleep wait

      downloadable.clear_cache
      retry
    end

    sig { override.params(filename: Pathname).void }
    def verify_download_integrity(filename) = downloadable.verify_download_integrity(filename)

    sig { override.returns(String) }
    def download_name = downloadable.download_name

    private

    sig { returns(Downloadable) }
    attr_reader :downloadable

    sig { returns(T::Boolean) }
    attr_reader :pour
  end
end
