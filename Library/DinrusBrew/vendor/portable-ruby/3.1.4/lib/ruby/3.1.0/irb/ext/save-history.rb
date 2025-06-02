# frozen_string_literal: false
#   save-history.rb -
#   	$Release Version: 0.9.6$
#   	$Revision$
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#
#

module IRB
  module HistorySavingAbility # :nodoc:
  end

  class Context
    def init_save_history# :nodoc:
      unless (class<<@io;self;end).include?(HistorySavingAbility)
        @io.extend(HistorySavingAbility)
      end
    end

    # A copy of the default <code>IRB.conf[:SAVE_HISTORY]</code>
    def save_history
      IRB.conf[:SAVE_HISTORY]
    end

    remove_method(:save_history=) if method_defined?(:save_history=)
    # Sets <code>IRB.conf[:SAVE_HISTORY]</code> to the given +val+ and calls
    # #init_save_history with this context.
    #
    # Will store the number of +val+ entries of history in the #history_file
    #
    # Add the following to your +.irbrc+ to change the number of history
    # entries stored to 1000:
    #
    #     IRB.conf[:SAVE_HISTORY] = 1000
    def save_history=(val)
      IRB.conf[:SAVE_HISTORY] = val
      if val
        main_context = IRB.conf[:MAIN_CONTEXT]
        main_context = self unless main_context
        main_context.init_save_history
      end
    end

    # A copy of the default <code>IRB.conf[:HISTORY_FILE]</code>
    def history_file
      IRB.conf[:HISTORY_FILE]
    end

    # Set <code>IRB.conf[:HISTORY_FILE]</code> to the given +hist+.
    def history_file=(hist)
      IRB.conf[:HISTORY_FILE] = hist
    end
  end

  module HistorySavingAbility # :nodoc:
    def HistorySavingAbility.extended(obj)
      IRB.conf[:AT_EXIT].push proc{obj.save_history}
      obj.load_history
      obj
    end

    def load_history
      return unless self.class.const_defined?(:HISTORY)
      history = self.class::HISTORY
      if history_file = IRB.conf[:HISTORY_FILE]
        history_file = File.expand_path(history_file)
      end
      history_file = IRB.rc_file("_history") unless history_file
      if File.exist?(history_file)
        open(history_file, "r:#{IRB.conf[:LC_MESSAGES].encoding}") do |f|
          f.each { |l|
            l = l.chomp
            if self.class == ReidlineInputMethod and history.last&.end_with?("\\")
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
      return unless self.class.const_defined?(:HISTORY)
      history = self.class::HISTORY
      if num = IRB.conf[:SAVE_HISTORY] and (num = num.to_i) != 0
        if history_file = IRB.conf[:HISTORY_FILE]
          history_file = File.expand_path(history_file)
        end
        history_file = IRB.rc_file("_history") unless history_file

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

        if File.exist?(history_file) && @loaded_history_mtime &&
           File.mtime(history_file) != @loaded_history_mtime
          history = history[@loaded_history_lines..-1]
          append_history = true
        end

        open(history_file, "#{append_history ? 'a' : 'w'}:#{IRB.conf[:LC_MESSAGES].encoding}", 0600) do |f|
          hist = history.map{ |l| l.split("\n").join("\\\n") }
          unless append_history
            begin
              hist = hist.last(num) if hist.size > num and num > 0
            rescue RangeError # bignum too big to convert into `long'
              # Do nothing because the bignum should be treated as inifinity
            end
          end
          f.puts(hist)
        end
      end
    end
  end
end
