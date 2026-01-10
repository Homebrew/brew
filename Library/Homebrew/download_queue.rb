# typed: strict
# frozen_string_literal: true

require "downloadable"
require "concurrent/promises"
require "concurrent/executors"
require "retryable_download"
require "resource"
require "utils/output"

module Homebrew
  class DownloadQueue
    include Utils::Output::Mixin

    sig { params(retries: Integer, force: T::Boolean, pour: T::Boolean).returns(T.nilable(DownloadQueue)) }
    def self.new_if_concurrency_enabled(retries: 1, force: false, pour: false)
      return if Homebrew::EnvConfig.download_concurrency <= 1

      new(retries:, force:, pour:)
    end

    sig { params(retries: Integer, force: T::Boolean, pour: T::Boolean).void }
    def initialize(retries: 1, force: false, pour: false)
      @concurrency = T.let(EnvConfig.download_concurrency, Integer)
      @quiet = T.let(@concurrency > 1, T::Boolean)
      @tries = T.let(retries + 1, Integer)
      @force = force
      @pour = pour
      @pool = T.let(Concurrent::FixedThreadPool.new(concurrency), Concurrent::FixedThreadPool)
      @tty = T.let($stdout.tty?, T::Boolean)
      @spinner = T.let(nil, T.nilable(Spinner))
      @symlink_targets = T.let({}, T::Hash[Pathname, T::Set[Downloadable]])
    end

    sig {
      params(
        downloadable:      Downloadable,
        check_attestation: T::Boolean,
      ).void
    }
    def enqueue(downloadable, check_attestation: false)
      cached_location = downloadable.cached_download

      @symlink_targets[cached_location] ||= Set.new
      targets = @symlink_targets.fetch(cached_location)
      targets << downloadable

      downloads[downloadable] ||= Concurrent::Promises.future_on(
        pool, RetryableDownload.new(downloadable, tries:, pour:),
        force, quiet, check_attestation
      ) do |download, force, quiet, check_attestation|
        download.clear_cache if force
        download.fetch(quiet:)
        if check_attestation && downloadable.is_a?(Bottle)
          Utils::Attestation.check_attestation(downloadable, quiet: true)
        end
        create_symlinks_for_shared_download(cached_location)
      end
    end

    sig { void }
    def fetch
      return if downloads.empty?

      context_before_fetch = Context.current

      if concurrency == 1
        downloads.each do |downloadable, promise|
          promise.wait!
        rescue ChecksumMismatchError => e
          ofail "#{downloadable.download_queue_type} reports different checksum: #{e.expected}"
        rescue => e
          raise e unless bottle_manifest_error?(downloadable, e)
        end
      else
        message_length_max = downloads.keys.map { |download| download.download_queue_message.length }.max || 0
        remaining_downloads = downloads.dup.to_a
        previous_pending_line_count = 0

        begin
          stdout_print_and_flush_if_tty Tty.hide_cursor

          output_message = lambda do |downloadable, future, last|
            status = status_from_future(future)
            exception = future.reason if future.rejected?
            next 1 if bottle_manifest_error?(downloadable, exception)

            message = downloadable.download_queue_message
            if tty
              message = message_with_progress(downloadable, future, message, message_length_max)
              stdout_print_and_flush "#{status} #{message}#{"\n" unless last}"
            elsif status
              $stderr.puts "#{status} #{message}"
            end

            if future.rejected?
              if exception.is_a?(ChecksumMismatchError)
                actual = Digest::SHA256.file(downloadable.cached_download).hexdigest
                actual_message, expected_message = align_checksum_mismatch_message(downloadable.download_queue_type)

                ofail "#{actual_message} #{exception.expected}"
                puts "#{expected_message} #{actual}"
                next 2
              elsif exception.is_a?(CannotInstallFormulaError)
                cached_download = downloadable.cached_download
                cached_download.unlink if cached_download&.exist?
                raise exception
              else
                message = future.reason.to_s
                ofail message
                next message.count("\n")
              end
            end

            1
          end

          until remaining_downloads.empty?
            begin
              finished_states = [:fulfilled, :rejected]

              finished_downloads, remaining_downloads = remaining_downloads.partition do |_, future|
                finished_states.include?(future.state)
              end

              finished_downloads.each do |downloadable, future|
                previous_pending_line_count -= 1
                stdout_print_and_flush_if_tty Tty.clear_to_end
                output_message.call(downloadable, future, false)
              end

              previous_pending_line_count = 0
              max_lines = [concurrency, Tty.height].min
              remaining_downloads.each_with_index do |(downloadable, future), i|
                break if previous_pending_line_count >= max_lines

                stdout_print_and_flush_if_tty Tty.clear_to_end
                last = i == max_lines - 1 || i == remaining_downloads.count - 1
                previous_pending_line_count += output_message.call(downloadable, future, last)
              end

              if previous_pending_line_count.positive?
                if (previous_pending_line_count - 1).zero?
                  stdout_print_and_flush_if_tty Tty.move_cursor_beginning
                else
                  stdout_print_and_flush_if_tty Tty.move_cursor_up_beginning(previous_pending_line_count - 1)
                end
              end

              sleep 0.05
            # We want to catch all exceptions to ensure we can cancel any
            # running downloads and flush the TTY.
            rescue Exception # rubocop:disable Lint/RescueException
              remaining_downloads.each do |_, future|
                # FIXME: Implement cancellation of running downloads.
              end

              cancel

              if previous_pending_line_count.positive?
                stdout_print_and_flush_if_tty Tty.move_cursor_down(previous_pending_line_count - 1)
              end

              raise
            end
          end
        ensure
          stdout_print_and_flush_if_tty Tty.show_cursor
        end
      end

      # Restore the pre-parallel fetch context to avoid e.g. quiet state bleeding out from threads.
      Context.current = context_before_fetch

      downloads.clear
    end

    sig { params(message: String).void }
    def stdout_print_and_flush_if_tty(message)
      stdout_print_and_flush(message) if $stdout.tty?
    end

    sig { params(message: String).void }
    def stdout_print_and_flush(message)
      $stdout.print(message)
      $stdout.flush
    end

    sig { void }
    def shutdown
      pool.shutdown
      pool.wait_for_termination
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
      # FIXME: Implement graceful cancellation of running downloads based on
      #        https://ruby-concurrency.github.io/concurrent-ruby/master/Concurrent/Cancellation.html
      #        instead of killing the whole thread pool.
      pool.kill
    end

    sig { returns(Concurrent::FixedThreadPool) }
    attr_reader :pool

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
        "#{Tty.blue}#{spinner}#{Tty.reset}" if tty
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

    sig { returns(Spinner) }
    def spinner
      @spinner ||= Spinner.new
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
      size, unit = disk_usage_readable_size_unit(fetched_size, precision:)
      formatted_fetched_size = format(size_formatting_string, size:, unit:)

      total_size = downloadable.total_size
      formatted_total_size = if future.fulfilled?
        formatted_fetched_size
      elsif total_size
        size, unit = disk_usage_readable_size_unit(total_size, precision:)
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

    class Spinner
      FRAMES = [
        "⠋",
        "⠙",
        "⠚",
        "⠞",
        "⠖",
        "⠦",
        "⠴",
        "⠲",
        "⠳",
        "⠓",
      ].freeze

      sig { void }
      def initialize
        @start = T.let(Time.now, Time)
        @i = T.let(0, Integer)
      end

      sig { returns(String) }
      def to_s
        now = Time.now
        if @start + 0.1 < now
          @start = now
          @i = (@i + 1) % FRAMES.count
        end

        FRAMES.fetch(@i)
      end
    end
  end
end
