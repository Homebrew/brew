# frozen_string_literal: true
#
#   output-method.rb - output methods used by irb
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#

module IRB
  # An abstract output class for IO in irb. This is mainly used internally by
  # IRB::Notifier. You can define your own output method to use with Irb.new,
  # or Context.new
  class OutputMethod
    # Open this method to implement your own output method, raises a
    # NotImplementedError if you don't define #print in your own class.
    def print(*opts)
      raise NotImplementedError
    end

    # Prints the given +opts+, with a newline delimiter.
    def printn(*opts)
      print opts.join(" "), "\n"
    end

    # Extends IO#printf to format the given +opts+ for Kernel#sprintf using
    # #parse_printf_format
    def printf(format, *opts)
      if /(%*)%I/ =~ format
        format, opts = parse_printf_format(format, opts)
      end
      print sprintf(format, *opts)
    end

    # Returns an array of the given +format+ and +opts+ to be used by
    # Kernel#sprintf, if there was a successful Regexp match in the given
    # +format+ from #printf
    #
    #     %
    #     <flag>  [#0- +]
    #     <minimum field width> (\*|\*[1-9][0-9]*\$|[1-9][0-9]*)
    #     <precision>.(\*|\*[1-9][0-9]*\$|[1-9][0-9]*|)?
    #     #<length modifier>(hh|h|l|ll|L|q|j|z|t)
    #     <conversion specifier>[diouxXeEfgGcsb%]
    def parse_printf_format(format, opts)
      return format, opts if $1.size % 2 == 1
    end

    # Calls #print on each element in the given +objs+, followed by a newline
    # character.
    def puts(*objs)
      for obj in objs
        print(*obj)
        print "\n"
      end
    end

    # Prints the given +objs+ calling Object#inspect on each.
    #
    # See #puts for more detail.
    def pp(*objs)
      puts(*objs.collect{|obj| obj.inspect})
    end

    # Prints the given +objs+ calling Object#inspect on each and appending the
    # given +prefix+.
    #
    # See #puts for more detail.
    def ppx(prefix, *objs)
      puts(*objs.collect{|obj| prefix+obj.inspect})
    end

  end

  # A standard output printer
  class StdioOutputMethod < OutputMethod
    # Prints the given +opts+ to standard output, see IO#print for more
    # information.
    def print(*opts)
      STDOUT.print(*opts)
    end
  end
end
