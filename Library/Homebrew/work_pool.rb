# typed: strict
# frozen_string_literal: true

require "concurrent/promises"
require "concurrent/executors"

module Homebrew
  # A generic thread pool for running work items in parallel with result collection
  # and live TTY progress reporting.
  # Shared by {DownloadQueue} and {Cleanup} to avoid duplicating concurrency logic.
  class WorkPool
    include Utils::Output::Mixin

    # Animated spinner for progress display.
    class Spinner
      FRAMES = T.let(["⠋", "⠙", "⠚", "⠞", "⠖", "⠦", "⠴", "⠲", "⠳", "⠓"].freeze, T::Array[String])

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

    sig { returns(Concurrent::FixedThreadPool) }
    attr_reader :pool

    sig { returns(Integer) }
    attr_reader :concurrency

    sig { returns(T::Hash[T.untyped, Concurrent::Promises::Future]) }
    attr_reader :futures

    sig { params(concurrency: Integer).void }
    def initialize(concurrency: Homebrew::EnvConfig.download_concurrency)
      @concurrency = T.let([concurrency, 1].max, Integer)
      @pool = T.let(Concurrent::FixedThreadPool.new(@concurrency), Concurrent::FixedThreadPool)
      @futures = T.let({}, T::Hash[T.untyped, Concurrent::Promises::Future])
      @tty = T.let($stdout.tty?, T::Boolean)
      @dumb_tty = T.let(ENV["TERM"] == "dumb", T::Boolean)
      @spinner = T.let(nil, T.nilable(Spinner))
    end

    # Submit a work item to the pool.
    sig {
      type_parameters(:U)
        .params(
          item:  T.untyped,
          args:  T.untyped,
          block: T.untyped,
        ).returns(Concurrent::Promises::Future)
    }
    def submit(item, *args, &block)
      future = Concurrent::Promises.future_on(pool, item, *args, &block)
      @futures[item] = future
      future
    end

    # Wait for all work to complete with optional live TTY progress reporting.
    sig {
      params(
        items:        T.nilable(T::Hash[T.untyped, Concurrent::Promises::Future]),
        quiet:        T::Boolean,
        on_interrupt: T.nilable(T.proc.params(arg0: Exception).void),
        status_block: T.nilable(T.proc.params(arg0: Concurrent::Promises::Future).returns(T.nilable(String))),
        message_block: T.nilable(T.proc.params(arg0: T.untyped, arg1: Concurrent::Promises::Future, arg2: T::Boolean).returns(String)),
      ).void
    }
    def wait_with_progress(items: nil, quiet: false, on_interrupt: nil, status_block: nil, message_block: nil)
      futures_to_wait = items || @futures
      return if futures_to_wait.empty?

      if quiet
        futures_to_wait.each_value(&:wait!)
        return
      end

      to_stderr = !tty_with_cursor_move_support?

      # Sequential fallback for non-TTY or single-item pools.
      if to_stderr || futures_to_wait.length <= 1
        futures_to_wait.each do |item, future|
          future.wait!
          render_item(item, future, status_block, message_block, final: true, last: false, to_stderr:)
        end
        return
      end

      remaining_items = futures_to_wait.to_a
      previous_pending_line_count = 0

      begin
        $stdout.print Tty.hide_cursor
        $stdout.flush

        until remaining_items.empty?
          finished_states = [:fulfilled, :rejected]
          finished, remaining_items = remaining_items.partition { |_, f| finished_states.include?(f.state) }

          finished.each do |item, future|
            previous_pending_line_count -= 1
            render_item(item, future, status_block, message_block, final: true, last: false)
            $stdout.print Tty.clear_to_end
            $stdout.flush
          end

          previous_pending_line_count = 0
          max_lines = [concurrency, Tty.height].min
          remaining_items.each_with_index do |(item, future), i|
            break if previous_pending_line_count >= max_lines

            last = i == max_lines - 1 || i == remaining_items.count - 1
            previous_pending_line_count += render_item(item, future, status_block, message_block, final: false, last:)
            $stdout.print Tty.clear_to_end
            $stdout.flush
          end

          if previous_pending_line_count.positive?
            move_up = previous_pending_line_count - 1
            $stdout.print(move_up.zero? ? Tty.move_cursor_beginning : Tty.move_cursor_up_beginning(move_up))
            $stdout.flush
          end

          sleep 0.05
        end
      rescue Exception => e # rubocop:disable Lint/RescueException
        on_interrupt&.call(e)

        if previous_pending_line_count.positive? && tty_with_cursor_move_support?
          $stdout.print Tty.move_cursor_down(previous_pending_line_count - 1)
          $stdout.flush
        end

        raise
      ensure
        $stdout.print Tty.show_cursor
        $stdout.flush
      end
    end

    # Shut down the pool and wait for all work to complete.
    sig { void }
    def shutdown
      pool.shutdown
      pool.wait_for_termination
    end

    private

    sig {
      params(
        item:          T.untyped,
        future:        Concurrent::Promises::Future,
        status_block:  T.nilable(T.proc.params(arg0: Concurrent::Promises::Future).returns(T.nilable(String))),
        message_block: T.nilable(T.proc.params(arg0: T.untyped, arg1: Concurrent::Promises::Future, arg2: T::Boolean).returns(String)),
        final:         T::Boolean,
        last:          T::Boolean,
        to_stderr:     T::Boolean,
      ).returns(Integer)
    }
    def render_item(item, future, status_block, message_block, final:, last:, to_stderr: false)
      status = if status_block
        status_block.call(future)
      else
        default_status_from_future(future)
      end

      message = if message_block
        message_block.call(item, future, final)
      else
        item.to_s
      end

      out = to_stderr ? $stderr : $stdout
      out.print "#{status} #{message}#{"\n" unless last}"
      out.flush

      message.count("\n") + 1
    end

    sig { params(future: Concurrent::Promises::Future).returns(T.nilable(String)) }
    def default_status_from_future(future)
      case future.state
      when :fulfilled then "✔︎"
      when :rejected then "✘"
      when :pending, :processing
        "#{Tty.blue}#{spinner}#{Tty.reset}"
      else
        raise "Unknown state: #{future.state}"
      end
    end

    sig { returns(T::Boolean) }
    def tty_with_cursor_move_support?
      @tty && !@dumb_tty
    end

    sig { returns(Spinner) }
    def spinner
      @spinner ||= Spinner.new
    end
  end
end
