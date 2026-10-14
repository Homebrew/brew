# typed: strict
# frozen_string_literal: true

require "utils/tty"

# Keeps a spinner below a build's output, followed by any step progress the
# current build log shows from e.g. Ninja (`[12/345]`) or CMake (`[ 42%]`).
class BuildProgress
  STEP_PROGRESS = %r{\A\[(\d+)/(\d+)\]}
  PERCENT_PROGRESS = /\A\[\s*(\d+)%\]/
  REDRAW_INTERVAL = 0.1
  LOG_CHECK_INTERVAL = 0.5
  LOG_TAIL_SIZE = 65536
  # How a pseudo-terminal echoes a typed Ctrl-C.
  INTERRUPT_ECHO = "^C"

  sig { returns(T::Boolean) }
  def self.tty?
    return false if !$stdout.tty? || !$stderr.tty?

    ENV["TERM"] != "dumb"
  end

  sig { params(logs: Pathname).void }
  def initialize(logs)
    require "download_queue"

    @logs = logs
    @start_time = T.let(Time.now, Time)
    @spinner = T.let(Homebrew::DownloadQueue::Spinner.new, Homebrew::DownloadQueue::Spinner)
    # `Tty` isn't thread-safe, so resolve its colours and width before drawing in a thread.
    @spinner_colour = T.let(Tty.blue.to_s, String)
    @reset = T.let(Tty.reset.to_s, String)
    Tty.width
    @progress = T.let(nil, T.nilable(String))
    @progress_checked_at = T.let(nil, T.nilable(Time))
    @drawn = T.let(false, T::Boolean)
    @at_line_start = T.let(true, T::Boolean)
    @interrupted = T.let(false, T::Boolean)
  end

  # Copies `input` to `output` until EOF, keeping the status line below it.
  sig { params(input: IO, output: T.any(IO, StringIO)).void }
  def forward(input, output)
    loop do
      if input.wait_readable(REDRAW_INTERVAL)
        begin
          data = input.readpartial(65536)
        rescue EOFError, Errno::EIO
          break
        end

        output.write("#{Tty.move_cursor_beginning}#{Tty.clear_to_end}") if @drawn
        output.write(data)
        @drawn = false
        # Progress is no longer interesting once the build is being interrupted.
        @interrupted ||= data.start_with?(INTERRUPT_ECHO)
        @at_line_start = data.end_with?("\n")
      end
      next if @interrupted || !@at_line_start

      output.write("#{Tty.move_cursor_beginning}#{Tty.clear_to_end}#{Tty.truncate(status)}")
      @drawn = true
    end
  end

  # Clears the status line.
  sig { params(output: T.any(IO, StringIO)).void }
  def finish(output)
    return unless @drawn

    output.write("#{Tty.move_cursor_beginning}#{Tty.clear_to_end}")
    @drawn = false
  end

  sig { returns(String) }
  def status
    checked_at = @progress_checked_at
    if checked_at.nil? || Time.now - checked_at >= LOG_CHECK_INTERVAL
      @progress = log_progress
      @progress_checked_at = Time.now
    end
    "#{@spinner_colour}#{@spinner}#{@reset} #{@progress}"
  end

  private

  # The step progress in the most recently written log of this build.
  sig { returns(T.nilable(String)) }
  def log_progress
    log = @logs.glob("*.log")
               .reject { |path| path.basename.to_s.match?(/\.(?:cc|sandbox)\.log\z/) }
               .select { |path| path.mtime >= @start_time }
               .max_by(&:mtime)
    return if log.nil?

    File.binread(log, LOG_TAIL_SIZE, [log.size - LOG_TAIL_SIZE, 0].max).to_s.lines.reverse_each do |line|
      if (match = line.match(STEP_PROGRESS))
        done = match[1].to_i
        total = match[2].to_i
        return "#{done}/#{total} (#{done * 100 / [total, 1].max}%)"
      elsif (match = line.match(PERCENT_PROGRESS))
        return "#{match[1]}%"
      end
    end
    nil
  rescue SystemCallError
    # The log was removed while reading it.
    nil
  end
end
