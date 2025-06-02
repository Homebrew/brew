# frozen_string_literal: false
#
#   history.rb -
#   	$Release Version: 0.9.6$
#   	$Revision$
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#
#

module IRB # :nodoc:

  class Context

    NOPRINTING_IVARS.push "@eval_history_values"

    # See #set_last_value
    alias _set_last_value set_last_value

    def set_last_value(value)
      _set_last_value(value)

      if defined?(@eval_history) && @eval_history
        @eval_history_values.push @line_no, @last_value
        @workspace.evaluate self, "__ = IRB.CurrentContext.instance_eval{@eval_history_values}"
      end

      @last_value
    end

    remove_method :eval_history= if method_defined?(:eval_history=)
    # The command result history limit. This method is not available until
    # #eval_history= was called with non-nil value (directly or via
    # setting <code>IRB.conf[:EVAL_HISTORY]</code> in <code>.irbrc</code>).
    attr_reader :eval_history
    # Sets command result history limit. Default value is set from
    # <code>IRB.conf[:EVAL_HISTORY]</code>.
    #
    # +no+ is an Integer or +nil+.
    #
    # Returns +no+ of history items if greater than 0.
    #
    # If +no+ is 0, the number of history items is unlimited.
    #
    # If +no+ is +nil+, execution result history isn't used (default).
    #
    # History values are available via <code>__</code> variable, see
    # IRB::History.
    def eval_history=(no)
      if no
        if defined?(@eval_history) && @eval_history
          @eval_history_values.size(no)
        else
          @eval_history_values = History.new(no)
          IRB.conf[:__TMP__EHV__] = @eval_history_values
          @workspace.evaluate(self, "__ = IRB.conf[:__TMP__EHV__]")
          IRB.conf.delete(:__TMP_EHV__)
        end
      else
        @eval_history_values = nil
      end
      @eval_history = no
    end
  end

  # Represents history of results of previously evaluated commands.
  #
  # Available via <code>__</code> variable, only if <code>IRB.conf[:EVAL_HISTORY]</code>
  # or <code>IRB::CurrentContext().eval_history</code> is non-nil integer value
  # (by default it is +nil+).
  #
  # Example (in `irb`):
  #
  #    # Initialize history
  #    IRB::CurrentContext().eval_history = 10
  #    # => 10
  #
  #    # Perform some commands...
  #    1 + 2
  #    # => 3
  #    puts 'x'
  #    # x
  #    # => nil
  #    raise RuntimeError
  #    # ...error raised
  #
  #    # Inspect history (format is "<item number> <evaluated value>":
  #    __
  #    # => 1 10
  #    # 2 3
  #    # 3 nil
  #
  #    __[1]
  #    # => 10
  #
  class History

    def initialize(size = 16)  # :nodoc:
      @size = size
      @contents = []
    end

    def size(size) # :nodoc:
      if size != 0 && size < @size
        @contents = @contents[@size - size .. @size]
      end
      @size = size
    end

    # Get one item of the content (both positive and negative indexes work).
    def [](idx)
      begin
        if idx >= 0
          @contents.find{|no, val| no == idx}[1]
        else
          @contents[idx][1]
        end
      rescue NameError
        nil
      end
    end

    def push(no, val)  # :nodoc:
      @contents.push [no, val]
      @contents.shift if @size != 0 && @contents.size > @size
    end

    alias real_inspect inspect

    def inspect  # :nodoc:
      if @contents.empty?
        return real_inspect
      end

      unless (last = @contents.pop)[1].equal?(self)
        @contents.push last
        last = nil
      end
      str = @contents.collect{|no, val|
        if val.equal?(self)
          "#{no} ...self-history..."
        else
          "#{no} #{val.inspect}"
        end
      }.join("\n")
      if str == ""
        str = "Empty."
      end
      @contents.push last if last
      str
    end
  end
end
