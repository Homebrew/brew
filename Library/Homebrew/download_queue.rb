# typed: strict
# frozen_string_literal: true

require "downloadable"
require "concurrent/promises"
require "concurrent/executors"
require "concurrent/atomic/atomic_boolean"
require "retryable_download"
require "resource"
require "utils/output"
require "work_pool"

module Homebrew
  # Raised when a download is cancelled cooperatively.
  class CancelledDownloadError < StandardError; end

  # Manages a queue of concurrent downloads with cooperative cancellation support.
  class DownloadQueue
    include Utils::Output::Mixin

    sig { params(retries: Integer, force: T::Boolean, pour: T::Boolean).void }
    def initialize(retries: 1, force: false, pour: false)
      @concurrency = T.let(EnvConfig.download_concurrency, Integer)
      @quiet = T.let(@concurrency > 1, T::Boolean)
      @tries = T.let(retries + 1, Integer)
      @force = force
      @pour = pour
      @work_pool = T.let(WorkPool.new(concurrency:), WorkPool)
      @tty = T.let($stdout.tty?, T::Boolean)
      @dumb_tty = T.let(ENV["TERM"] == "dumb", T::Boolean)
      @symlink_targets = T.let({}, T::Hash[Pathname, T::Set[Downloadable]])
      @downloads_by_location = T.let({}, T::Hash[Pathname, Concurrent::Promises::Future])
      @cancelled = T.let(Concurrent::AtomicBoolean.new(false), Concurrent::AtomicBoolean)
      @spinner = T.let(nil, T.nilable(WorkPool::Spinner))
    end

    sig {
      params(
        downloadable:      Downloadable,
        check_attestation: T::Boolean,
      ).void
    }
    def enqueue(downloadable, check_attestation: false)
      @cancelled.make_false
      cached_location = downloadable.cached_download

      @symlink_targets[cached_location] ||= Set.new
      targets = @symlink_targets.fetch(cached_location)
      targets << downloadable

      @downloads_by_location[cached_location] ||= @work_pool.submit(
        RetryableDownload.new(downloadable, tries:, pour:),
        @cancelled, force, quiet, check_attestation
      ) do |download, cancelled, force, quiet, check_attestation|
        raise CancelledDownloadError if cancelled.true?

        download.clear_cache if force
        download.fetch(quiet:)
        raise CancelledDownloadError if cancelled.true?

        if check_attestation && downloadable.is_a?(Bottle)
          Utils::Attestation.check_attestation(downloadable, quiet: true)
        end
        create_symlinks_for_shared_download(cached_location)
      end

      downloads[downloadable] = @downloads_by_location.fetch(cached_location)
    end

    sig { void }
    def fetch
      return if downloads.empty?

      context_before_fetch = Context.current

      if concurrency == 1
        downloads.each do |downloadable, promise|
          promise.wait!
        rescue CancelledDownloadError
          next
        rescue ChecksumMismatchError => e
          ofail "#{downloadable.download_queue_type} reports different checksum: #{e.expected}"
        rescue => e
          raise e unless bottle_manifest_error?(downloadable, e)
        end
      else
        message_length_max = downloads.keys.map { |download| download.download_queue_message.length }.max || 0

        @work_pool.wait_with_progress(
          items:         downloads,
          on_interrupt:  ->(_e) { cancel },
          status_block:  ->(future) { status_from_future(future) },
          message_block: lambda { |downloadable, future, final|
            exception = future.reason if future.rejected?
            return "Cancelled" if exception.is_a?(CancelledDownloadError)
            return "Bottle manifest error" if bottle_manifest_error?(downloadable, exception)

            message = downloadable.download_queue_message
            if tty_with_cursor_move_support?
              message = message_with_progress(downloadable, future, message, message_length_max)
            end

            if final && future.rejected?
              if exception.is_a?(ChecksumMismatchError)
                actual = Digest::SHA256.file(downloadable.cached_download).hexdigest
                actual_message, expected_message = align_checksum_mismatch_message(downloadable.download_queue_type)
                ofail "#{actual_message} #{exception.expected}"
                puts "#{expected_message} #{actual}"
              elsif exception.is_a?(CannotInstallFormulaError)
                cached_download = downloadable.cached_download
                cached_download.unlink if cached_download&.exist?
                raise exception
              else
                err_message = if exception.is_a?(DownloadError) && exception.cause.is_a?(ErrorDuringExecution)
                  cause = T.cast(exception.cause, ErrorDuringExecution)
                  if (stderr_output = cause.stderr.presence)
                    "#{stderr_output}#{cause.message}"
                  else
                    cause.message
                  end
                else
                  future.reason.to_s
                end
                ofail err_message
              end
            end

            message
          },
        )
      end

      # Restore the pre-parallel fetch context to avoid e.g. quiet state bleeding out from threads.
      Context.current = context_before_fetch

      downloads.clear
      @downloads_by_location.clear
      @symlink_targets.clear
    end

    sig { void }
    def shutdown
      @work_pool.shutdown
    end

    private

    sig { params(cached_location: Pathname).void }
    def create_symlinks_for_shared_download(cached_location)
      targets = @symlink_targets.fetch(cached_location, Set.new)
      targets.each do |target|
        downloader = target.downloader
        next unless downloader.is_a?(AbstractFileDownloadStrategy)

        symlink_location = downloader.symlink_location
        next if symlink_location.symlink? && symlink_location.exist?

        downloader.create_symlink_to_cached_download(cached_location)
      end
    end

    sig { params(downloadable: Downloadable, exception: T.nilable(Exception)).returns(T::Boolean) }
    def bottle_manifest_error?(downloadable, exception)
      return false if exception.nil?

      downloadable.is_a?(Resource::BottleManifest) || exception.is_a?(Resource::BottleManifest::Error)
    end

    sig { void }
    def cancel
      # Signal cooperative cancellation to all running downloads.
      # Downloads check the cancelled flag at key points and will raise
      # CancelledDownloadError when cancelled.
      @cancelled.make_true
    end

    sig { returns(WorkPool) }
    attr_reader :work_pool

    sig { returns(Integer) }
    attr_reader :concurrency

    sig { returns(Integer) }
    attr_reader :tries

    sig { returns(T::Boolean) }
    attr_reader :force

    sig { returns(T::Boolean) }
    attr_reader :quiet

    sig { returns(T::Boolean) }
    attr_reader :pour

    sig { returns(T::Boolean) }
    attr_reader :tty

    sig { returns(T::Boolean) }
    def tty_with_cursor_move_support?
      tty && !@dumb_tty
    end

    sig { returns(T::Hash[Downloadable, Concurrent::Promises::Future]) }
    def downloads
      @downloads ||= T.let({}, T.nilable(T::Hash[Downloadable, Concurrent::Promises::Future]))
    end

    sig { params(future: Concurrent::Promises::Future).returns(T.nilable(String)) }
    def status_from_future(future)
      case future.state
      when :fulfilled
        if tty
          "#{Tty.green}✔︎#{Tty.reset}"
        else
          "✔︎"
        end
      when :rejected
        if tty
          "#{Tty.red}✘#{Tty.reset}"
        else
          "✘"
        end
      when :pending, :processing
        "#{Tty.blue}#{spinner}#{Tty.reset}" if tty_with_cursor_move_support?
      else
        raise future.state.to_s
      end
    end

    sig { params(downloadable_type: String).returns(T::Array[String]) }
    def align_checksum_mismatch_message(downloadable_type)
      actual_checksum_output = "#{downloadable_type} reports different checksum:"
      expected_checksum_output = "SHA-256 checksum of downloaded file:"

      # `.max` returns `T.nilable(Integer)`, use `|| 0` to pass the typecheck
      rightpad = [actual_checksum_output, expected_checksum_output].map(&:size).max || 0

      # 7 spaces are added to align with `ofail` message, which adds `Error: ` at the beginning
      [actual_checksum_output.ljust(rightpad), (" " * 7) + expected_checksum_output.ljust(rightpad)]
    end

    sig { returns(WorkPool::Spinner) }
    def spinner
      @spinner ||= WorkPool::Spinner.new
    end
    sig { params(downloadable: Downloadable, future: Concurrent::Promises::Future, message: String, message_length_max: Integer).returns(String) }
    def message_with_progress(downloadable, future, message, message_length_max)
      tty_width = Tty.width
      return message unless tty_width.positive?

      available_width = tty_width - 2
      fetched_size = downloadable.fetched_size
      return message[0, available_width].to_s if fetched_size.blank?

      precision = 1
      size_length = 5
      unit_length = 2
      size_formatting_string = "%<size>#{size_length}.#{precision}f%<unit>#{unit_length}s"
      size, unit = Formatter.disk_usage_readable_size_unit(fetched_size, precision:)
      formatted_fetched_size = format(size_formatting_string, size:, unit:)

      total_size = downloadable.total_size
      formatted_total_size = if future.fulfilled?
        formatted_fetched_size
      elsif total_size
        size, unit = Formatter.disk_usage_readable_size_unit(total_size, precision:)
        format(size_formatting_string, size:, unit:)
      else
        # fill in the missing spaces for the size if we don't have it yet.
        "-" * (size_length + unit_length)
      end

      max_phase_length = 11
      phase = format("%-<phase>#{max_phase_length}s", phase: downloadable.phase.to_s.capitalize)
      progress = " #{phase} #{formatted_fetched_size}/#{formatted_total_size}"
      bar_length = [4, available_width - progress.length - message_length_max - 1].max
      if downloadable.phase == :downloading && total_size
        percent = (fetched_size.to_f / [1, total_size].max).clamp(0.0, 1.0)
        bar_used = (percent * bar_length).round
        bar_completed = "#" * bar_used
        bar_pending = " " * (bar_length - bar_used)
        progress = " #{bar_completed}#{bar_pending}#{progress}"
      end
      message_length = available_width - progress.length
      return message[0, available_width].to_s unless message_length.positive?

      "#{message[0, message_length].to_s.ljust(message_length)}#{progress}"
    end
  end

  sig { returns(DownloadQueue) }
  def self.default_download_queue
    @default_download_queue ||= T.let(DownloadQueue.new, T.nilable(DownloadQueue))
  end

  sig { void }
  def self.shutdown_default_download_queue
    @default_download_queue&.shutdown
  end

  at_exit do
    Homebrew.shutdown_default_download_queue
  end
end
