# frozen_string_literal: true

require_relative 'period'

class Logger
  # Device used for logging messages.
  class LogDevice
    include Period

    attr_reader :dev
    attr_reader :filename
    include MonitorMixin

    def initialize(
      log = nil, shift_age: nil, shift_size: nil, shift_period_suffix: nil,
      binmode: false, reraise_write_errors: [], skip_header: false
    )
      @dev = @filename = @shift_age = @shift_size = @shift_period_suffix = nil
      @binmode = binmode
      @reraise_write_errors = reraise_write_errors
      @skip_header = skip_header
      mon_initialize
      set_dev(log)
      set_file(shift_age, shift_size, shift_period_suffix) if @filename
    end

    def write(message)
      handle_write_errors("writing") do
        synchronize do
          if @shift_age and @dev.respond_to?(:stat)
            handle_write_errors("shifting") {check_shift_log}
          end
          handle_write_errors("writing") {@dev.write(message)}
        end
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

    def reopen(log = nil, shift_age: nil, shift_size: nil, shift_period_suffix: nil, binmode: nil)
      # reopen the same filename if no argument, do nothing for IO
      log ||= @filename if @filename
      @binmode = binmode unless binmode.nil?
      if log
        synchronize do
          if @filename and @dev
            @dev.close rescue nil # close only file opened by Logger
            @filename = nil
          end
          set_dev(log)
          set_file(shift_age, shift_size, shift_period_suffix) if @filename
        end
      end
      self
    end

  private

    # :stopdoc:

    MODE = File::WRONLY | File::APPEND
    # TruffleRuby < 24.2 does not have File::SHARE_DELETE
    if File.const_defined? :SHARE_DELETE
      MODE_TO_OPEN = MODE | File::SHARE_DELETE | File::BINARY
    else
      MODE_TO_OPEN = MODE | File::BINARY
    end
    MODE_TO_CREATE = MODE_TO_OPEN | File::CREAT | File::EXCL

    def set_dev(log)
      if log.respond_to?(:write) and log.respond_to?(:close)
        @dev = log
        if log.respond_to?(:path) and path = log.path
          if File.exist?(path)
            @filename = path
          end
        end
      else
        @dev = open_logfile(log)
        @filename = log
      end
    end

    def set_file(shift_age, shift_size, shift_period_suffix)
      @shift_age = shift_age || @shift_age || 7
      @shift_size = shift_size || @shift_size || 1048576
      @shift_period_suffix = shift_period_suffix || @shift_period_suffix || '%Y%m%d'

      unless @shift_age.is_a?(Integer)
        base_time = @dev.respond_to?(:stat) ? @dev.stat.mtime : Time.now
        @next_rotate_time = next_rotate_time(base_time, @shift_age)
      end
    end

    if MODE_TO_OPEN == MODE
      def fixup_mode(dev)
        dev
      end
    else
      def fixup_mode(dev)
        return dev if @binmode
        dev.autoclose = false
        old_dev = dev
        dev = File.new(dev.fileno, mode: MODE, path: dev.path)
        old_dev.close
        PathAttr.set_path(dev, filename) if defined?(PathAttr)
        dev
      end
    end

    def open_logfile(filename)
      begin
        dev = File.open(filename, MODE_TO_OPEN)
      rescue Errno::ENOENT
        create_logfile(filename)
      else
        dev = fixup_mode(dev)
        dev.sync = true
        dev.binmode if @binmode
        dev
      end
    end

    def create_logfile(filename)
      begin
        logdev = File.open(filename, MODE_TO_CREATE)
        logdev.flock(File::LOCK_EX)
        logdev = fixup_mode(logdev)
        logdev.sync = true
        logdev.binmode if @binmode
        add_log_header(logdev) unless @skip_header
        logdev.flock(File::LOCK_UN)
        logdev
      rescue Errno::EEXIST
        # file is created by another process
        open_logfile(filename)
      end
    end

    def handle_write_errors(mesg)
      yield
    rescue *@reraise_write_errors
      raise
    rescue
      warn("log #{mesg} failed. #{$!}")
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

    def lock_shift_log
      retry_limit = 8
      retry_sleep = 0.1
      begin
        File.open(@filename, MODE_TO_OPEN) do |lock|
          lock.flock(File::LOCK_EX) # inter-process locking. will be unlocked at closing file
          if File.identical?(@filename, lock) and File.identical?(lock, @dev)
            yield # log shifting
          else
            # log shifted by another process (i-node before locking and i-node after locking are different)
            @dev.close rescue nil
            @dev = open_logfile(@filename)
          end
        end
        true
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

    def shift_log_age
      (@shift_age-3).downto(0) do |i|
        if FileTest.exist?("#{@filename}.#{i}")
          File.rename("#{@filename}.#{i}", "#{@filename}.#{i+1}")
        end
      end
      shift_log_file("#{@filename}.0")
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
      shift_log_file(age_file)
    end

    def shift_log_file(shifted)
      stat = @dev.stat
      @dev.close rescue nil
      File.rename(@filename, shifted)
      @dev = create_logfile(@filename)
      mode, uid, gid = stat.mode, stat.uid, stat.gid
      begin
        @dev.chmod(mode) if mode
        mode = nil
        @dev.chown(uid, gid)
      rescue Errno::EPERM
        if mode
          # failed to chmod, probably nothing can do more.
        elsif uid
          uid = nil
          retry # to change gid only
        end
      end
      return true
    end
  end
end

File.open(__FILE__) do |f|
  File.new(f.fileno, autoclose: false, path: "").path
rescue IOError
  module PathAttr               # :nodoc:
    attr_reader :path

    def self.set_path(file, path)
      file.extend(self).instance_variable_set(:@path, path)
    end
  end
end
