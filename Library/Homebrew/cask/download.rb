# typed: strict
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

    sig { returns(::Cask::Cask) }
    attr_reader :cask

    sig { params(cask: ::Cask::Cask, quarantine: T.nilable(T::Boolean)).void }
    def initialize(cask, quarantine: nil)
      super()

      @cask = cask
      @quarantine = quarantine
    end

    sig { override.returns(T.nilable(::URL)) }
    def url
      return if (cask_url = cask.url).nil?

      @url ||= ::URL.new(cask_url.to_s, cask_url.specs)
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

    sig { params(timeout: T.nilable(T.any(Float, Integer))).returns([T.nilable(Time), Integer]) }
    def time_file_size(timeout: nil)
      raise ArgumentError, "not supported for this download strategy" unless downloader.is_a?(CurlDownloadStrategy)

      T.cast(downloader, CurlDownloadStrategy).resolved_time_file_size(timeout:)
    end

    sig { returns(Pathname) }
    def basename
      downloader.basename
    end

    sig { override.params(filename: Pathname).void }
    def verify_download_integrity(filename)
      if no_checksum_defined? && !official_cask_tap?
        opoo "No checksum defined for cask '#{@cask}', skipping verification."
        return
      end

      super
    end

    sig { override.returns(String) }
    def download_queue_name = "#{cask.token} (#{version})"

    sig { override.returns(String) }
    def download_queue_type = "Cask"

    private

    sig { params(path: Pathname).void }
    def quarantine(path)
      return if @quarantine.nil?
      return unless Quarantine.available?

      if @quarantine
        Quarantine.cask!(cask: @cask, download_path: path)
      else
        Quarantine.release!(download_path: path)
      end
    end

    sig { returns(T::Boolean) }
    def official_cask_tap?
      tap = @cask.tap
      return false if tap.blank?

      tap.official?
    end

    sig { returns(T::Boolean) }
    def no_checksum_defined?
      @cask.sha256 == :no_check
    end

    sig { override.returns(T::Boolean) }
    def silence_checksum_missing_error?
      no_checksum_defined? && official_cask_tap?
    end

    sig { override.returns(T.nilable(::URL)) }
    def determine_url
      url
    end

    sig { override.returns(Pathname) }
    def cache
      Cache.path
    end

    sig { override.returns(String) }
    def download_name
      url_basename = super
      version = self.version
      url = self.url
      return url_basename if version.nil? || url.nil?

      temp_downloader = download_strategy.new(url.to_s, url_basename, version, mirrors: [], cache:, **url.specs)
      return url_basename unless temp_downloader.is_a?(AbstractFileDownloadStrategy)

      potential_symlink_length = temp_downloader.symlink_location.basename.to_s.length
      max_filesystem_symlink_length = 255

      return url_basename if potential_symlink_length < max_filesystem_symlink_length

      cask.full_token.gsub("/", "--")
    end
  end
end
