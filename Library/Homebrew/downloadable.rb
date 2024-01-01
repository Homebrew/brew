# typed: true
# frozen_string_literal: true

require "url"
require "checksum"

# @api private
class Downloadable
  include Context
  extend T::Helpers

  abstract!

  sig { returns(T.nilable(URL)) }
  attr_reader :url

  sig { returns(T.nilable(Checksum)) }
  attr_reader :checksum

  sig { returns(T::Array[String]) }
  attr_reader :mirrors

  sig { void }
  def initialize
    @mirrors = T.let([], T::Array[String])
  end

  def initialize_dup(other)
    super
    @checksum = @checksum.dup
    @mirrors = @mirrors.dup
    @version = @version.dup
  end

  sig { override.returns(T.self_type) }
  def freeze
    @checksum.freeze
    @mirrors.freeze
    @version.freeze
    super
  end

  sig { returns(T::Boolean) }
  def downloaded?
    cached_download.exist?
  end

  sig { returns(Pathname) }
  def cached_download
    downloader.cached_location
  end

  sig { void }
  def clear_cache
    downloader.clear_cache
  end

  sig { returns(T.nilable(Version)) }
  def version
    return @version if @version && !@version.null?

    version = determine_url&.version
    version unless version&.null?
  end

  sig { returns(T.class_of(AbstractDownloadStrategy)) }
  def download_strategy
    @download_strategy ||= determine_url&.download_strategy
  end

  sig { returns(AbstractDownloadStrategy) }
  def downloader
    @downloader ||= begin
      primary_url, *mirrors = determine_url_mirrors
      raise ArgumentError, "attempted to use a Downloadable without a URL!" if primary_url.blank?

      download_strategy.new(primary_url, download_name, version,
                            mirrors: mirrors, cache: cache, **T.must(@url).specs)
    end
  end

  sig { params(verify_download_integrity: T::Boolean, timeout: T.nilable(T.any(Integer, Float))).returns(Pathname) }
  def fetch(verify_download_integrity: true, timeout: nil)
    cache.mkpath

    begin
      downloader.fetch(timeout: timeout)
    rescue ErrorDuringExecution, CurlDownloadStrategyError => e
      raise DownloadError.new(self, e)
    end

    download = cached_download
    verify_download_integrity(download) if verify_download_integrity
    download
  end

  sig { params(filename: Pathname).void }
  def verify_download_integrity(filename)
    if filename.file?
      ohai "Verifying checksum for '#{filename.basename}'" if verbose?
      filename.verify_checksum(checksum)
    end
  rescue ChecksumMissingError
    opoo <<~EOS
      Cannot verify integrity of '#{filename.basename}'.
      No checksum was provided.
      For your reference, the checksum is:
        sha256 "#{filename.sha256}"
    EOS
  end

  sig { overridable.returns(String) }
  def download_name
    File.basename(determine_url.to_s)
  end

  private

  sig { overridable.returns(T.nilable(URL)) }
  def determine_url
    @url
  end

  sig { overridable.returns(T::Array[String]) }
  def determine_url_mirrors
    [determine_url.to_s, *mirrors].uniq
  end

  sig { overridable.returns(Pathname) }
  def cache
    HOMEBREW_CACHE
  end
end
