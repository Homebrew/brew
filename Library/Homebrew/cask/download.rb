# typed: strict
# frozen_string_literal: true

require "downloadable"
require "fileutils"
require "unpack_strategy"
require "cask/cache"
require "cask/caskroom"
require "cask/quarantine"
require "cask/utils"

module Cask
  # A download corresponding to a {Cask}.
  class Download
    include Downloadable

    include Context

    sig { returns(::Cask::Cask) }
    attr_reader :cask

    sig {
      params(
        cask:        ::Cask::Cask,
        quarantine:  T.nilable(T::Boolean),
        require_sha: T::Boolean,
      ).void
    }
    def initialize(cask, quarantine: nil, require_sha: false)
      super()

      @cask = cask
      @quarantine = quarantine
      @require_sha = require_sha
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
      verify_has_sha if @require_sha
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

    sig { returns(UnpackStrategy) }
    def primary_container
      @primary_container ||= T.let(
        begin
          downloaded_path = cask.download || fetch(quiet: true)
          UnpackStrategy.detect(downloaded_path, type: cask.container&.type, merge_xattrs: true)
        end,
        T.nilable(UnpackStrategy),
      )
    end

    sig { params(to: Pathname, verbose: T::Boolean, container: T.nilable(UnpackStrategy)).void }
    def extract_primary_container(to:, verbose:, container: nil)
      odebug "Extracting primary container"

      container ||= primary_container
      raise "unexpected nil primary_container" unless container

      odebug "Using container class #{container.class} for #{container.path}"

      if (nested_container = cask.container&.nested)
        Dir.mktmpdir("cask-installer", HOMEBREW_TEMP) do |tmpdir|
          tmpdir = Pathname(tmpdir)
          container.extract(to: tmpdir, basename:, verbose:)

          FileUtils.chmod_R "+rw", tmpdir/nested_container, force: true, verbose: verbose

          UnpackStrategy.detect(tmpdir/nested_container, merge_xattrs: true)
                        .extract_nestedly(to:, verbose:)
        end
      else
        container.extract_nestedly(to:, basename:, verbose:)
      end

      return unless @quarantine
      return unless Quarantine.available?

      Quarantine.propagate(from: container.path, to:)
    end

    sig { params(target_dir: Pathname).void }
    def process_rename_operations(target_dir:)
      return if cask.rename.empty?

      odebug "Processing rename operations in #{target_dir}"

      cask.rename.each do |rename_operation|
        odebug "Renaming #{rename_operation.from} to #{rename_operation.to}"
        rename_operation.perform_rename(target_dir)
      end
    end

    sig { returns(Pathname) }
    def staged_path_from_download_queue
      HOMEBREW_PREFIX/"var/homebrew/tmp/.caskroom"/cask.staged_path.relative_path_from(Caskroom.path)
    end

    sig { returns(Pathname) }
    def staged_path_from_download_queue_marker
      Pathname("#{staged_path_from_download_queue}.staged")
    end

    sig { params(command: T.class_of(SystemCommand)).void }
    def purge_staged_from_download_queue(command: SystemCommand)
      staged_marker = staged_path_from_download_queue_marker
      Utils.gain_permissions_remove(staged_marker, command:) if staged_marker.symlink? || staged_marker.exist?

      staged_path = staged_path_from_download_queue
      Utils.gain_permissions_remove(staged_path, command:) if staged_path.exist?

      staged_path.parent.rmdir_if_possible
      staged_path.parent.parent.rmdir_if_possible
    end

    sig { override.params(download: Pathname, pour: T::Boolean).returns(T::Boolean) }
    def stage_from_download_queue?(download, pour:)
      return false unless pour
      return false if cask.staged_path.exist? || staged_path_from_download_queue_marker.exist?

      UnpackStrategy.detect(download, type:         cask.container&.type,
                                      merge_xattrs: true).dependencies.all? do |dependency|
        case dependency
        when Formula
          dependency.any_version_installed? && dependency.optlinked?
        when Cask
          dependency.installed?
        end
      end
    end

    sig { override.params(download: Pathname, pour: T::Boolean).void }
    def stage_from_download_queue(download, pour:)
      return unless stage_from_download_queue?(download, pour:)

      purge_staged_from_download_queue
      cask.download ||= download
      extract_primary_container(
        to:        staged_path_from_download_queue,
        verbose:   false,
        container: UnpackStrategy.detect(
          download,
          type:         cask.container&.type,
          merge_xattrs: true,
        ),
      )
      process_rename_operations(target_dir: staged_path_from_download_queue)
      FileUtils.ln_s(staged_path_from_download_queue, staged_path_from_download_queue_marker)
    # Catch any exception type here to clean up partial queued extractions.
    rescue Exception # rubocop:disable Lint/RescueException
      ignore_interrupts do
        purge_staged_from_download_queue
      end
      raise
    end

    sig { override.returns(T::Boolean) }
    def downloaded_and_valid?
      return false unless super

      quarantine(cached_download)
      true
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

    sig { void }
    def verify_has_sha
      return if @cask.sha256 != :no_check

      raise CaskError, <<~EOS
        Cask '#{@cask}' does not have a sha256 checksum defined.
        This means you have the #{Formatter.identifier("--require-sha")} option set, perhaps in your `$HOMEBREW_CASK_OPTS`.
      EOS
    end

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
    def download_name = cask.token
  end
end
