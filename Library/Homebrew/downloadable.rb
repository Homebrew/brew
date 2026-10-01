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

  # Remembers the SHA-256 digest of each file hashed in this process, keyed
  # by its resolved path, size and modification time, so a file is hashed
  # at most once per on-disk state no matter how many download objects or
  # verifications reference it.
  class VerificationCache
    include Context
    include Utils::Output::Mixin

    # Raised by the integration-test-only check in `Pathname#sha256` when an
    # unchanged file is hashed again without this cache being involved.
    class RepeatedHashingError < RuntimeError; end

    CACHE_MEDIATED_HASHING_KEY = :homebrew_verification_cache_mediated_hashing

    class << self
      # The identity and change metadata that determine whether a file can
      # be considered unchanged on disk: the device, inode, size and
      # nanosecond modification and change times ensure a replaced or
      # rewritten file is treated as new, even when its size and
      # modification time are restored, as the change time cannot be set
      # from userland.
      sig { params(filename: Pathname).returns(T.nilable(String)) }
      def on_disk_state(filename)
        stat = filename.stat
        "#{stat.dev}|#{stat.ino}|#{stat.size}|" \
          "#{stat.mtime.to_i}.#{stat.mtime.nsec}|#{stat.ctime.to_i}.#{stat.ctime.nsec}"
      rescue SystemCallError
        nil
      end

      # Guards against repeated verification creeping in without this cache:
      # every `Pathname#sha256` call reports here and, in `brew` commands
      # run by integration tests only, rehashing an unchanged file outside
      # the cache raises. Hashing is cheap there while a repeat in real use
      # would rehash a download that can be hundreds of megabytes.
      sig { params(filename: Pathname).void }
      def check_repeated_hashing(filename)
        return if ENV["HOMEBREW_CHECK_REPEATED_HASHING"].blank?

        state = on_disk_state(filename)
        return if state.nil?

        require "concurrent/set"
        @hashed_states ||= T.let(Concurrent::Set.new, T.nilable(Concurrent::Set))
        # `add?` atomically records the state and reports whether it was new.
        return unless @hashed_states.add?(state).nil?
        return if Thread.current[CACHE_MEDIATED_HASHING_KEY]

        raise RepeatedHashingError, <<~ERROR
          Refusing to hash '#{filename}' again: its unchanged contents were already hashed in this process.
          Verify downloads through `Downloadable#verify_download_integrity` so its digest cache reuses the existing hash.
          This check only runs when `$HOMEBREW_CHECK_REPEATED_HASHING` is set, e.g. in Homebrew's integration tests.
        ERROR
      end

      sig { type_parameters(:U).params(_block: T.proc.returns(T.type_parameter(:U))).returns(T.type_parameter(:U)) }
      def while_hashing_through_cache(&_block)
        Thread.current[CACHE_MEDIATED_HASHING_KEY] = true
        yield
      ensure
        Thread.current[CACHE_MEDIATED_HASHING_KEY] = nil
      end
    end

    sig { void }
    def initialize
      require "concurrent/map"

      @digests = T.let(Concurrent::Map.new, Concurrent::Map)
    end

    # Verifies the file against the checksum. Repeated verifications of a
    # file unchanged on disk only compare against its remembered digest.
    sig { params(filename: Pathname, checksum: T.nilable(Checksum)).void }
    def verify(filename, checksum)
      raise ChecksumMissingError if checksum.blank?

      ohai "Verifying checksum for '#{filename.basename}'" if verbose?
      actual = Checksum.new(sha256(filename))
      return if checksum == actual

      raise ChecksumMismatchError.new(filename, checksum, actual)
    end

    # The file's SHA-256 digest, hashing its contents at most once per
    # on-disk state in this process.
    sig { params(filename: Pathname).returns(String) }
    def sha256(filename)
      key = key_for(filename)
      if key && (digest = @digests[key])
        odebug "Skipping SHA-256 hashing for '#{filename.basename}' (unchanged since last hashed in this run)"
        return digest
      end

      digest = self.class.while_hashing_through_cache { filename.sha256 }
      # Only remember the digest when the file did not change while its
      # contents were being hashed.
      @digests[key] = digest if key && key == key_for(filename)
      digest
    end

    # Forgets the remembered digest for the file's current on-disk state,
    # for callers that suspect its contents changed without the metadata
    # that keys this cache changing, e.g. in-place corruption suggested by
    # a failed extraction.
    sig { params(filename: Pathname).void }
    def invalidate!(filename)
      key = key_for(filename)
      @digests.delete(key) if key
    end

    private

    # The resolved path unifies verifications through a symlink with those
    # through its target, e.g. a download verified once at its cache
    # location and once through the cache's symlink to it.
    sig { params(filename: Pathname).returns(T.nilable(String)) }
    def key_for(filename)
      state = self.class.on_disk_state(filename)
      return if state.nil?

      "#{filename.realpath}|#{state}"
    rescue SystemCallError
      nil
    end
  end

  class << self
    sig { returns(VerificationCache) }
    def verification_cache
      @verification_cache ||= T.let(VerificationCache.new, T.nilable(VerificationCache))
    end
  end

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

  sig { overridable.returns(T::Boolean) }
  def downloaded_and_valid?
    return false unless cached_download.file?
    return false if checksum.blank?

    with_context(quiet: true) { verify_download_integrity(cached_download) }
    true
  rescue ChecksumMismatchError
    false
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
    @download_strategy ||= begin
      url = determine_url
      raise ArgumentError, "attempted to use a `Downloadable` without a URL!" if url.nil?

      url.download_strategy
    end
  end

  sig { overridable.returns(AbstractDownloadStrategy) }
  def downloader
    @downloader ||= begin
      primary_url, *mirrors = determine_url_mirrors
      url = determine_url
      raise ArgumentError, "attempted to use a `Downloadable` without a URL!" if url.nil? || primary_url.blank?

      download_strategy.new(primary_url, download_name, version,
                            mirrors:, cache:, **url.specs).tap do |downloader|
        if downloader.is_a?(CurlDownloadStrategy) &&
           AbstractDownloadStrategy.expand_deferred_environment_for?(downloader)
          downloader.allow_deferred_environment_expansion!
        end
      end
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

  sig { overridable.params(_download: Pathname, pour: T::Boolean).returns(T::Boolean) }
  def stage_from_download_queue?(_download, pour:)
    false
  end

  sig { overridable.returns(T.nilable(Pathname)) }
  def staged_path_from_download_queue; end

  sig { overridable.params(_download: Pathname, pour: T::Boolean).void }
  def stage_from_download_queue(_download, pour:); end

  sig { overridable.params(filename: Pathname).void }
  def verify_download_integrity(filename)
    verifying!

    if filename.file?
      Downloadable.verification_cache.verify(filename, checksum)
      verified!
    end
  rescue ChecksumMissingError
    return if silence_checksum_missing_error?

    opoo <<~EOS
      Cannot verify integrity of '#{filename.basename}'.
      No checksum was provided.
      For your reference, the checksum is:
        sha256 "#{Downloadable.verification_cache.sha256(filename)}"
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
