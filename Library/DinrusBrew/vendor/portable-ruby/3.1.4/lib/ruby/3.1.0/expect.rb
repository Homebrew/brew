# frozen_string_literal: true
$expect_verbose = false

# Expect library adds the IO instance method #expect, which does similar act to
# tcl's expect extension.
#
# In order to use this method, you must require expect:
#
#   require 'expect'
#
# Please see #expect for usage.
class IO
  # call-seq:
  #   IO#expect(pattern,timeout=9999999)                  ->  Array
  #   IO#expect(pattern,timeout=9999999) { |result| ... } ->  nil
  #
  # Reads from the IO until the given +pattern+ matches or the +timeout+ is over.
  #
  # It returns an array with the read buffer, followed by the matches.
  # If a block is given, the result is yielded to the block and returns nil.
  #
  # When called without a block, it waits until the input that matches the
  # given +pattern+ is obtained from the IO or the time specified as the
  # timeout passes. An array is returned when the pattern is obtained from the
  # IO. The first element of the array is the entire string obtained from the
  # IO until the pattern matches, followed by elements indicating which the
  # pattern which matched to the anchor in the regular expression.
  #
  # The optional timeout parameter defines, in seconds, the total time to wait
  # for the pattern.  If the timeout expires or eof is found, nil is returned
  # or yielded.  However, the buffer in a timeout session is kept for the next
  # expect call.  The default timeout is 9999999 seconds.
  def expect(pat,timeout=9999999)
    buf = ''.dup
    case pat
    when String
      e_pat = Regexp.new(Regexp.quote(pat))
    when Regexp
      e_pat = pat
    else
      raise TypeError, "unsupported pattern class: #{pat.class}"
    end
    @unusedBuf ||= ''
    while true
      if not @unusedBuf.empty?
        c = @unusedBuf.slice!(0)
      elsif !IO.select([self],nil,nil,timeout) or eof? then
        result = nil
        @unusedBuf = buf
        break
      else
        c = getc
      end
      buf << c
      if $expect_verbose
        STDOUT.print c
        STDOUT.flush
      end
      if mat=e_pat.match(buf) then
        result = [buf,*mat.captures]
        break
      end
    end
    if block_given? then
      yield result
    else
      return result
    end
    nil
  end
end
