# typed: strict
# frozen_string_literal: true

require "url"
require "checksum"
require "download_strategy"
require "utils/output"

module Downloadable
  include Context
  include Utils::Output::Mixin
  extend T::Helpers

  abstract!
  requires_ancestor { Kernel }

  sig { overridable.returns(T.nilable(T.any(String, URL))) }
  attr_reader :url

  sig { overridable.returns(T.nilable(Checksum)) }
  attr_reader :checksum

  sig { overridable.returns(T::Array[String]) }
  attr_reader :mirrors

  sig { overridable.returns(Symbol) }
  attr_accessor :phase

  sig { void }
  def downloading! = (@phase = :downloading)
  sig { void }
  def downloaded! = (@phase = :downloaded)
  sig { void }
  def verifying! = (@phase = :verifying)
  sig { void }
  def verified! = (@phase = :verified)
  sig { void }
  def extracting! = (@phase = :extracting)

  sig { void }
  def initialize
    @url = T.let(nil, T.nilable(URL))
    @checksum = T.let(nil, T.nilable(Checksum))
    @mirrors = T.let([], T::Array[String])
    @version = T.let(nil, T.nilable(Version))
    @download_strategy = T.let(nil, T.nilable(T::Class[AbstractDownloadStrategy]))
    @downloader = T.let(nil, T.nilable(AbstractDownloadStrategy))
    @download_name = T.let(nil, T.nilable(String))
    @phase = T.let(:preparing, Symbol)
  end

  sig { overridable.params(other: Downloadable).void }
  def initialize_dup(other)
    super
    @checksum = @checksum.dup
    @mirrors = @mirrors.dup
    @version = @version.dup
  end

  sig { overridable.returns(T.self_type) }
  def freeze
    @checksum.freeze
    @mirrors.freeze
    @version.freeze
    super
  end

  sig { returns(String) }
  def download_queue_name = download_name

  sig { abstract.returns(String) }
  def download_queue_type; end

  sig(:final) { returns(String) }
  def download_queue_message
    "#{download_queue_type} #{download_queue_name}"
  end

  sig(:final) { returns(T::Boolean) }
  def downloaded?
    cached_download.exist?
  end

  sig { overridable.returns(Pathname) }
  def cached_download
    downloader.cached_location
  end

  sig { overridable.void }
  def clear_cache
    downloader.clear_cache
  end

  # Total bytes downloaded if available.
  sig { overridable.returns(T.nilable(Integer)) }
  def fetched_size
    downloader.fetched_size
  end

  # Total download size if available.
  sig { overridable.returns(T.nilable(Integer)) }
  def total_size
    @total_size ||= T.let(downloader.total_size, T.nilable(Integer))
  end

  sig { overridable.returns(T.nilable(Version)) }
  def version
    return @version if @version && !@version.null?

    version = determine_url&.version
    version unless version&.null?
  end

  sig { overridable.returns(T::Class[AbstractDownloadStrategy]) }
  def download_strategy
    @download_strategy ||= T.must(determine_url).download_strategy
  end

  sig { overridable.returns(AbstractDownloadStrategy) }
  def downloader
    @downloader ||= begin
      primary_url, *mirrors = determine_url_mirrors
      raise ArgumentError, "attempted to use a `Downloadable` without a URL!" if primary_url.blank?

      download_strategy.new(primary_url, download_name, version,
                            mirrors:, cache:, **T.must(@url).specs)
    end
  end

  sig {
    overridable.params(
      verify_download_integrity: T::Boolean,
      timeout:                   T.nilable(T.any(Integer, Float)),
      quiet:                     T::Boolean,
    ).returns(Pathname)
  }
  def fetch(verify_download_integrity: true, timeout: nil, quiet: false)
    downloading!

    cache.mkpath

    begin
      downloader.quiet! if quiet
      downloader.fetch(timeout:)
    rescue ErrorDuringExecution, CurlDownloadStrategyError => e
      raise DownloadError.new(self, e)
    end

    downloaded!

    download = cached_download
    verify_download_integrity(download) if verify_download_integrity
    download
  end

  sig { overridable.params(filename: Pathname).void }
  def verify_download_integrity(filename)
    verifying!

    if filename.file?
      ohai "Verifying checksum for '#{filename.basename}'" if verbose?
      filename.verify_checksum(checksum)
      verified!
    end
  rescue ChecksumMissingError
    return if silence_checksum_missing_error?

    opoo <<~EOS
      Cannot verify integrity of '#{filename.basename}'.
      No checksum was provided.
      For your reference, the checksum is:
        sha256 "#{filename.sha256}"
    EOS
  end

  sig { returns(Integer) }
  def hash
    [self.class, cached_download].hash
  end

  sig { params(other: Object).returns(T::Boolean) }
  def eql?(other)
    return false if self.class != other.class

    other = T.cast(other, Downloadable)
    cached_download == other.cached_download
  end

  sig { returns(String) }
  def to_s
    short_cached_download = cached_download.to_s
                                           .delete_prefix("#{HOMEBREW_CACHE}/downloads/")
    "#<#{self.class}: #{short_cached_download}>"
  end

  private

  sig { overridable.returns(String) }
  def download_name
    @download_name ||= File.basename(determine_url.to_s).freeze
  end

  sig { overridable.returns(T::Boolean) }
  def silence_checksum_missing_error?
    false
  end

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
