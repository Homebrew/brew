# frozen_string_literal: true

require_relative 'period'

class Logger
  # Device used for logging messages.
  class LogDevice
    include Period

    attr_reader :dev
    attr_reader :filename
    include MonitorMixin

    def initialize(log = nil, shift_age: nil, shift_size: nil, shift_period_suffix: nil, binmode: false)
      @dev = @filename = @shift_age = @shift_size = @shift_period_suffix = nil
      @binmode = binmode
      mon_initialize
      set_dev(log)
      if @filename
        @shift_age = shift_age || 7
        @shift_size = shift_size || 1048576
        @shift_period_suffix = shift_period_suffix || '%Y%m%d'

        unless @shift_age.is_a?(Integer)
          base_time = @dev.respond_to?(:stat) ? @dev.stat.mtime : Time.now
          @next_rotate_time = next_rotate_time(base_time, @shift_age)
        end
      end
    end

    def write(message)
      begin
        synchronize do
          if @shift_age and @dev.respond_to?(:stat)
            begin
              check_shift_log
            rescue
              warn("log shifting failed. #{$!}")
            end
          end
          begin
            @dev.write(message)
          rescue
            warn("log writing failed. #{$!}")
          end
        end
      rescue Exception => ignored
        warn("log writing failed. #{ignored}")
      end
    end

    def close
      begin
        synchronize do
          @dev.close rescue nil
        end
      rescue Exception
        @dev.close rescue nil
      end
    end

    def reopen(log = nil)
      # reopen the same filename if no argument, do nothing for IO
      log ||= @filename if @filename
      if log
        synchronize do
          if @filename and @dev
            @dev.close rescue nil # close only file opened by Logger
            @filename = nil
          end
          set_dev(log)
        end
      end
      self
    end

  private

    def set_dev(log)
      if log.respond_to?(:write) and log.respond_to?(:close)
        @dev = log
        if log.respond_to?(:path)
          @filename = log.path
        end
      else
        @dev = open_logfile(log)
        @dev.sync = true
        @dev.binmode if @binmode
        @filename = log
      end
    end

    def open_logfile(filename)
      begin
        File.open(filename, (File::WRONLY | File::APPEND))
      rescue Errno::ENOENT
        create_logfile(filename)
      end
    end

    def create_logfile(filename)
      begin
        logdev = File.open(filename, (File::WRONLY | File::APPEND | File::CREAT | File::EXCL))
        logdev.flock(File::LOCK_EX)
        logdev.sync = true
        logdev.binmode if @binmode
        add_log_header(logdev)
        logdev.flock(File::LOCK_UN)
      rescue Errno::EEXIST
        # file is created by another process
        logdev = open_logfile(filename)
        logdev.sync = true
      end
      logdev
    end

    def add_log_header(file)
      file.write(
        "# Logfile created on %s by %s\n" % [Time.now.to_s, Logger::ProgName]
      ) if file.size == 0
    end

    def check_shift_log
      if @shift_age.is_a?(Integer)
        # Note: always returns false if '0'.
        if @filename && (@shift_age > 0) && (@dev.stat.size > @shift_size)
          lock_shift_log { shift_log_age }
        end
      else
        now = Time.now
        if now >= @next_rotate_time
          @next_rotate_time = next_rotate_time(now, @shift_age)
          lock_shift_log { shift_log_period(previous_period_end(now, @shift_age)) }
        end
      end
    end

    if /mswin|mingw|cygwin/ =~ RUBY_PLATFORM
      def lock_shift_log
        yield
      end
    else
      def lock_shift_log
        retry_limit = 8
        retry_sleep = 0.1
        begin
          File.open(@filename, File::WRONLY | File::APPEND) do |lock|
            lock.flock(File::LOCK_EX) # inter-process locking. will be unlocked at closing file
            if File.identical?(@filename, lock) and File.identical?(lock, @dev)
              yield # log shifting
            else
              # log shifted by another process (i-node before locking and i-node after locking are different)
              @dev.close rescue nil
              @dev = open_logfile(@filename)
              @dev.sync = true
            end
          end
        rescue Errno::ENOENT
          # @filename file would not exist right after #rename and before #create_logfile
          if retry_limit <= 0
            warn("log rotation inter-process lock failed. #{$!}")
          else
            sleep retry_sleep
            retry_limit -= 1
            retry_sleep *= 2
            retry
          end
        end
      rescue
        warn("log rotation inter-process lock failed. #{$!}")
      end
    end

    def shift_log_age
      (@shift_age-3).downto(0) do |i|
        if FileTest.exist?("#{@filename}.#{i}")
          File.rename("#{@filename}.#{i}", "#{@filename}.#{i+1}")
        end
      end
      @dev.close rescue nil
      File.rename("#{@filename}", "#{@filename}.0")
      @dev = create_logfile(@filename)
      return true
    end

    def shift_log_period(period_end)
      suffix = period_end.strftime(@shift_period_suffix)
      age_file = "#{@filename}.#{suffix}"
      if FileTest.exist?(age_file)
        # try to avoid filename crash caused by Timestamp change.
        idx = 0
        # .99 can be overridden; avoid too much file search with 'loop do'
        while idx < 100
          idx += 1
          age_file = "#{@filename}.#{suffix}.#{idx}"
          break unless FileTest.exist?(age_file)
        end
      end
      @dev.close rescue nil
      File.rename("#{@filename}", age_file)
      @dev = create_logfile(@filename)
      return true
    end
  end
end
