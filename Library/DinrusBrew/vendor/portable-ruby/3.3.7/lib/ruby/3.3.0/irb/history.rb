require "pathname"

module IRB
  module HistorySavingAbility # :nodoc:
    def support_history_saving?
      true
    end

    def reset_history_counter
      @loaded_history_lines = self.class::HISTORY.size
    end

    def load_history
      history = self.class::HISTORY

      if history_file = IRB.conf[:HISTORY_FILE]
        history_file = File.expand_path(history_file)
      end
      history_file = IRB.rc_file("_history") unless history_file
      if history_file && File.exist?(history_file)
        File.open(history_file, "r:#{IRB.conf[:LC_MESSAGES].encoding}") do |f|
          f.each { |l|
            l = l.chomp
            if self.class == RelineInputMethod and history.last&.end_with?("\\")
              history.last.delete_suffix!("\\")
              history.last << "\n" << l
            else
              history << l
            end
          }
        end
        @loaded_history_lines = history.size
        @loaded_history_mtime = File.mtime(history_file)
      end
    end

    def save_history
      history = self.class::HISTORY.to_a

      if num = IRB.conf[:SAVE_HISTORY] and (num = num.to_i) != 0
        if history_file = IRB.conf[:HISTORY_FILE]
          history_file = File.expand_path(history_file)
        end
        history_file = IRB.rc_file("_history") unless history_file

        # When HOME and XDG_CONFIG_HOME are not available, history_file might be nil
        return unless history_file

        # Change the permission of a file that already exists[BUG #7694]
        begin
          if File.stat(history_file).mode & 066 != 0
            File.chmod(0600, history_file)
          end
        rescue Errno::ENOENT
        rescue Errno::EPERM
          return
        rescue
          raise
        end

        if File.exist?(history_file) &&
           File.mtime(history_file) != @loaded_history_mtime
          history = history[@loaded_history_lines..-1] if @loaded_history_lines
          append_history = true
        end

        pathname = Pathname.new(history_file)
        unless Dir.exist?(pathname.dirname)
          warn "Warning: The directory to save IRB's history file does not exist. Please double check `IRB.conf[:HISTORY_FILE]`'s value."
          return
        end

        File.open(history_file, (append_history ? 'a' : 'w'), 0o600, encoding: IRB.conf[:LC_MESSAGES]&.encoding) do |f|
          hist = history.map{ |l| l.scrub.split("\n").join("\\\n") }
          unless append_history
            begin
              hist = hist.last(num) if hist.size > num and num > 0
            rescue RangeError # bignum too big to convert into `long'
              # Do nothing because the bignum should be treated as infinity
            end
          end
          f.puts(hist)
        end
      end
    end
  end
end
