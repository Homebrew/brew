# typed: strict
# frozen_string_literal: true

require "stringio"

module Homebrew
  class DownloadQueue
    # Keeps completed download rows above a transient frame of active downloads.
    # Ordinary output clears the active frame and nested fetches pause rendering.
    class Progress
      @current = T.let(nil, T.nilable(Progress))

      class << self
        sig { returns(T.nilable(Progress)) }
        attr_accessor :current
      end

      # Each completed row carries a callback, run after its output succeeds.
      sig { params(frame: T.proc.returns([T::Array[[String, T.proc.void]], T::Array[String]])).void }
      def initialize(&frame)
        @frame = frame
        @mutex = T.let(Thread::Mutex.new, Thread::Mutex)
        @stopped = T.let(Concurrent::Event.new, Concurrent::Event)
        @stdout = T.let($stdout, T.any(IO, StringIO))
        @stderr = T.let($stderr, T.any(IO, StringIO))
        @stderr_shares_terminal = T.let(false, T::Boolean)
        if @stdout.is_a?(IO) && @stderr.is_a?(IO) && @stderr.tty?
          @stderr_shares_terminal = File.identical?(@stdout, @stderr)
        end
        @visible = T.let(false, T::Boolean)
        @paused = T.let(0, Integer)
        @line_start = T.let(true, T::Boolean)
      end

      # Refreshes progress until the block returns, restoring both streams
      # even when preparation or rendering raises an exception.
      # Returns the block's result.
      sig { type_parameters(:U).params(_block: T.proc.returns(T.type_parameter(:U))).returns(T.type_parameter(:U)) }
      def run(&_block)
        self.class.current = self
        $stdout = Output.new(@stdout, self)
        $stderr = Output.new(@stderr, self)
        thread = Thread.new do
          Thread.current.report_on_exception = false
          until @stopped.wait(0.05)
            @mutex.synchronize do
              next if @paused.positive? || !@line_start

              finished, lines = @frame.call
              next if finished.empty? && lines.empty? && !@visible

              @stdout.print Tty.begin_synchronized_update
              clear
              finished.each do |message, report|
                @stdout.puts(message)
                @stdout.flush
                report.call
              end
              unless lines.empty?
                @stdout.print lines.join("\n")
                @stdout.print Tty.move_cursor_up_beginning(lines.length - 1) if lines.length > 1
                @stdout.print Tty.move_cursor_beginning
                @visible = true
              end
              @stdout.print Tty.end_synchronized_update
              @stdout.flush
            end
          end
        ensure
          @mutex.synchronize do
            @stdout.print Tty.end_synchronized_update
            clear
          end
        end
        yield
      ensure
        @stopped.set
        begin
          thread&.join
        rescue IOError, Errno::EPIPE, Errno::EIO
          # Progress output is cosmetic. Do not let a render failure abort the command.
          nil
        ensure
          $stdout = @stdout
          $stderr = @stderr
          self.class.current = nil
        end
      end

      # Suspends rendering while a fetch owns the terminal.
      sig { void }
      def pause
        @mutex.synchronize do
          @paused += 1
          clear
        end
      end

      # Resumes rendering after the matching pause.
      sig { void }
      def resume
        @mutex.synchronize { @paused -= 1 }
      end

      # Leaves partial lines alone until ordinary output completes the line.
      sig { params(stream: T.any(IO, StringIO), string: String).returns(Integer) }
      def write(stream, string)
        if !stream.equal?(@stdout) && (!stream.equal?(@stderr) || !@stderr_shares_terminal)
          return stream.write(string)
        end

        @mutex.synchronize do
          clear
          written = stream.write(string)
          # Fetches end with cursor controls, which do not start a partial line.
          string = Tty.strip_ansi(string) if @paused.positive?
          @line_start = string.end_with?("\n") unless string.empty?
          written
        end
      end

      private

      sig { void }
      def clear
        return unless @visible

        @visible = false
        @stdout.print "#{Tty.move_cursor_beginning}#{Tty.clear_to_end_of_screen}"
        @stdout.flush
      rescue IOError, Errno::EPIPE, Errno::EIO
        # Stop cosmetic redraws when the terminal can no longer be cleared.
        @stopped.set
      end

      # StringIO routes print/puts through write, including their newlines.
      class Output < StringIO
        extend Forwardable
        extend T::Generic

        Elem = type_member(:out) { { fixed: String } }

        def_delegators :@stream, :tty?, :isatty, :flush, :fileno, :to_io, :winsize, :sync, :sync=

        sig { params(stream: T.any(IO, StringIO), progress: Progress).void }
        def initialize(stream, progress)
          super()
          @stream = stream
          @progress = progress
        end

        sig { params(objects: Object).returns(Integer) }
        def write(*objects)
          @progress.write(@stream, objects.join)
        end
      end
      private_constant :Output
    end
  end
end
