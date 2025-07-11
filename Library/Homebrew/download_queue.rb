# typed: strict
# frozen_string_literal: true

require "downloadable"
require "concurrent/promises"
require "concurrent/executors"
require "retryable_download"

module Homebrew
  class DownloadQueue
    sig { params(concurrency: Integer, retries: Integer, force: T::Boolean).void }
    def initialize(concurrency:, retries:, force:)
      @concurrency = concurrency
      @quiet = T.let(concurrency > 1, T::Boolean)
      @tries = T.let(retries + 1, Integer)
      @force = force
      @pool = T.let(Concurrent::FixedThreadPool.new(concurrency), Concurrent::FixedThreadPool)
    end

    sig { params(downloadable: T.any(Resource, Bottle, Cask::Download)).void }
    def enqueue(downloadable)
      downloads[downloadable] ||= Concurrent::Promises.future_on(
        pool, RetryableDownload.new(downloadable, tries:), force, quiet
      ) do |download, force, quiet|
        download.clear_cache if force
        download.fetch(quiet:)
      end
    end

    sig { void }
    def start
      if concurrency == 1
        downloads.each do |downloadable, promise|
          promise.wait!
        rescue ChecksumMismatchError => e
          opoo "#{downloadable.download_type.capitalize} reports different checksum: #{e.expected}"
          Homebrew.failed = true if downloadable.is_a?(Resource::Patch)
        end
      else
        spinner = Spinner.new
        remaining_downloads = downloads.dup.to_a
        previous_pending_line_count = 0

        begin
          $stdout.print Tty.hide_cursor
          $stdout.flush

          output_message = lambda do |downloadable, future, last|
            status = case future.state
            when :fulfilled
              "#{Tty.green}✔︎#{Tty.reset}"
            when :rejected
              "#{Tty.red}✘#{Tty.reset}"
            when :pending, :processing
              "#{Tty.blue}#{spinner}#{Tty.reset}"
            else
              raise future.state.to_s
            end

            message = "#{downloadable.download_type.capitalize} #{downloadable.name}"
            $stdout.print "#{status} #{message}#{"\n" unless last}"
            $stdout.flush

            if future.rejected?
              if (e = future.reason).is_a?(ChecksumMismatchError)
                opoo "#{downloadable.download_type.capitalize} reports different checksum: #{e.expected}"
                Homebrew.failed = true if downloadable.is_a?(Resource::Patch)
                next 2
              else
                message = future.reason.to_s
                onoe message
                Homebrew.failed = true
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
                $stdout.print Tty.clear_to_end
                $stdout.flush
                output_message.call(downloadable, future, false)
              end

              previous_pending_line_count = 0
              max_lines = [concurrency, Tty.height].min
              remaining_downloads.each_with_index do |(downloadable, future), i|
                break if previous_pending_line_count >= max_lines

                $stdout.print Tty.clear_to_end
                $stdout.flush
                last = i == max_lines - 1 || i == remaining_downloads.count - 1
                previous_pending_line_count += output_message.call(downloadable, future, last)
              end

              if previous_pending_line_count.positive?
                if (previous_pending_line_count - 1).zero?
                  $stdout.print Tty.move_cursor_beginning
                else
                  $stdout.print Tty.move_cursor_up_beginning(previous_pending_line_count - 1)
                end
                $stdout.flush
              end

              sleep 0.05
            rescue Interrupt
              remaining_downloads.each do |_, future|
                # FIXME: Implement cancellation of running downloads.
              end

              cancel

              if previous_pending_line_count.positive?
                $stdout.print Tty.move_cursor_down(previous_pending_line_count - 1)
                $stdout.flush
              end

              raise
            end
          end
        ensure
          $stdout.print Tty.show_cursor
          $stdout.flush
        end
      end
    end

    sig { void }
    def shutdown
      pool.shutdown
      pool.wait_for_termination
    end

    private

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

    sig { returns(T::Hash[T.any(Resource, Bottle, Cask::Download), Concurrent::Promises::Future]) }
    def downloads
      @downloads ||= T.let({}, T.nilable(T::Hash[T.any(Resource, Bottle, Cask::Download),
                                                 Concurrent::Promises::Future]))
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
