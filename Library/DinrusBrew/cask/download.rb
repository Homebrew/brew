# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "downloadable"
require "fileutils"
require "cask/cache"
require "cask/quarantine"

module Cask
  # A download corresponding to a {Cask}.
  class Download
    include Downloadable

    include Context

    attr_reader :cask

    def initialize(cask, quarantine: nil)
      super()

      @cask = cask
      @quarantine = quarantine
    end

    sig { override.returns(String) }
    def name
      cask.token
    end

    sig { override.returns(T.nilable(::URL)) }
    def url
      return if cask.url.nil?

      @url ||= ::URL.new(cask.url.to_s, cask.url.specs)
    end

    sig { override.returns(T.nilable(::Checksum)) }
    def checksum
      @checksum ||= cask.sha256 if cask.sha256 != :no_check
    end

    sig { override.returns(T.nilable(Version)) }
    def version
      return if cask.version.nil?

      @version ||= Version.new(cask.version)
    end

    sig {
      override
        .params(quiet:                     T.nilable(T::Boolean),
                verify_download_integrity: T::Boolean,
                timeout:                   T.nilable(T.any(Integer, Float)))
        .returns(Pathname)
    }
    def fetch(quiet: nil, verify_download_integrity: true, timeout: nil)
      downloader.quiet! if quiet

      begin
        super(verify_download_integrity: false, timeout:)
      rescue DownloadError => e
        error = CaskError.new("Download failed on Cask '#{cask}' with message: #{e.cause}")
        error.set_backtrace e.backtrace
        raise error
      end

      downloaded_path = cached_download
      quarantine(downloaded_path)
      self.verify_download_integrity(downloaded_path) if verify_download_integrity
      downloaded_path
    end

    def time_file_size(timeout: nil)
      raise ArgumentError, "not supported for this download strategy" unless downloader.is_a?(CurlDownloadStrategy)

      T.cast(downloader, CurlDownloadStrategy).resolved_time_file_size(timeout:)
    end

    def basename
      downloader.basename
    end

    sig { override.params(filename: Pathname).void }
    def verify_download_integrity(filename)
      official_cask_tap = @cask.tap&.official?
      if @cask.sha256 == :no_check && !official_cask_tap
        opoo "No checksum defined for cask '#{@cask}', skipping verification."
        return
      end

      super
    end

    sig { override.returns(String) }
    def download_name
      cask.token
    end

    sig { override.returns(String) }
    def download_type
      "cask"
    end

    private

    def quarantine(path)
      return if @quarantine.nil?
      return unless Quarantine.available?

      if @quarantine
        Quarantine.cask!(cask: @cask, download_path: path)
      else
        Quarantine.release!(download_path: path)
      end
    end

    sig { override.returns(T.nilable(::URL)) }
    def determine_url
      url
    end

    sig { override.returns(Pathname) }
    def cache
      Cache.path
    end
  end
end
