# coding: binary
# frozen_string_literal: true
#--
#= Info
#  'OpenSSL for Ruby 2' project
#  Copyright (C) 2001 GOTOU YUUZOU <gotoyuzo@notwork.org>
#  All rights reserved.
#
#= Licence
#  This program is licensed under the same licence as Ruby.
#  (See the file 'LICENCE'.)
#++

##
# OpenSSL IO buffering mix-in module.
#
# This module allows an OpenSSL::SSL::SSLSocket to behave like an IO.
#
# You typically won't use this module directly, you can see it implemented in
# OpenSSL::SSL::SSLSocket.

module OpenSSL::Buffering
  include Enumerable

  # A buffer which will retain binary encoding.
  class Buffer < String
    BINARY = Encoding::BINARY

    def initialize
      super

      force_encoding(BINARY)
    end

    def << string
      if string.encoding == BINARY
        super(string)
      else
        super(string.b)
      end

      return self
    end

    alias concat <<
  end

  ##
  # The "sync mode" of the SSLSocket.
  #
  # See IO#sync for full details.

  attr_accessor :sync

  ##
  # Default size to read from or write to the SSLSocket for buffer operations.

  BLOCK_SIZE = 1024*16

  ##
  # Creates an instance of OpenSSL's buffering IO module.

  def initialize(*)
    super
    @eof = false
    @rbuffer = Buffer.new
    @sync = @io.sync
  end

  #
  # for reading.
  #
  private

  ##
  # Fills the buffer from the underlying SSLSocket

  def fill_rbuff
    begin
      @rbuffer << self.sysread(BLOCK_SIZE)
    rescue Errno::EAGAIN
      retry
    rescue EOFError
      @eof = true
    end
  end

  ##
  # Consumes _size_ bytes from the buffer

  def consume_rbuff(size=nil)
    if @rbuffer.empty?
      nil
    else
      size = @rbuffer.size unless size
      @rbuffer.slice!(0, size)
    end
  end

  public

  # call-seq:
  #   ssl.getbyte => 81
  #
  # Get the next 8bit byte from `ssl`.  Returns `nil` on EOF
  def getbyte
    read(1)&.ord
  end

  ##
  # Reads _size_ bytes from the stream.  If _buf_ is provided it must
  # reference a string which will receive the data.
  #
  # See IO#read for full details.

  def read(size=nil, buf=nil)
    if size == 0
      if buf
        buf.clear
        return buf
      else
        return ""
      end
    end
    until @eof
      break if size && size <= @rbuffer.size
      fill_rbuff
    end
    ret = consume_rbuff(size) || ""
    if buf
      buf.replace(ret)
      ret = buf
    end
    (size && ret.empty?) ? nil : ret
  end

  ##
  # Reads at most _maxlen_ bytes from the stream.  If _buf_ is provided it
  # must reference a string which will receive the data.
  #
  # See IO#readpartial for full details.

  def readpartial(maxlen, buf=nil)
    if maxlen == 0
      if buf
        buf.clear
        return buf
      else
        return ""
      end
    end
    if @rbuffer.empty?
      begin
        return sysread(maxlen, buf)
      rescue Errno::EAGAIN
        retry
      end
    end
    ret = consume_rbuff(maxlen)
    if buf
      buf.replace(ret)
      ret = buf
    end
    ret
  end

  ##
  # Reads at most _maxlen_ bytes in the non-blocking manner.
  #
  # When no data can be read without blocking it raises
  # OpenSSL::SSL::SSLError extended by IO::WaitReadable or IO::WaitWritable.
  #
  # IO::WaitReadable means SSL needs to read internally so read_nonblock
  # should be called again when the underlying IO is readable.
  #
  # IO::WaitWritable means SSL needs to write internally so read_nonblock
  # should be called again after the underlying IO is writable.
  #
  # OpenSSL::Buffering#read_nonblock needs two rescue clause as follows:
  #
  #   # emulates blocking read (readpartial).
  #   begin
  #     result = ssl.read_nonblock(maxlen)
  #   rescue IO::WaitReadable
  #     IO.select([io])
  #     retry
  #   rescue IO::WaitWritable
  #     IO.select(nil, [io])
  #     retry
  #   end
  #
  # Note that one reason that read_nonblock writes to the underlying IO is
  # when the peer requests a new TLS/SSL handshake.  See openssl the FAQ for
  # more details.  http://www.openssl.org/support/faq.html
  #
  # By specifying a keyword argument _exception_ to +false+, you can indicate
  # that read_nonblock should not raise an IO::Wait*able exception, but
  # return the symbol +:wait_writable+ or +:wait_readable+ instead. At EOF,
  # it will return +nil+ instead of raising EOFError.

  def read_nonblock(maxlen, buf=nil, exception: true)
    if maxlen == 0
      if buf
        buf.clear
        return buf
      else
        return ""
      end
    end
    if @rbuffer.empty?
      return sysread_nonblock(maxlen, buf, exception: exception)
    end
    ret = consume_rbuff(maxlen)
    if buf
      buf.replace(ret)
      ret = buf
    end
    ret
  end

  ##
  # Reads the next "line" from the stream.  Lines are separated by _eol_.  If
  # _limit_ is provided the result will not be longer than the given number of
  # bytes.
  #
  # _eol_ may be a String or Regexp.
  #
  # Unlike IO#gets the line read will not be assigned to +$_+.
  #
  # Unlike IO#gets the separator must be provided if a limit is provided.

  def gets(eol=$/, limit=nil)
    idx = @rbuffer.index(eol)
    until @eof
      break if idx
      fill_rbuff
      idx = @rbuffer.index(eol)
    end
    if eol.is_a?(Regexp)
      size = idx ? idx+$&.size : nil
    else
      size = idx ? idx+eol.size : nil
    end
    if size && limit && limit >= 0
      size = [size, limit].min
    end
    consume_rbuff(size)
  end

  ##
  # Executes the block for every line in the stream where lines are separated
  # by _eol_.
  #
  # See also #gets

  def each(eol=$/)
    while line = self.gets(eol)
      yield line
    end
  end
  alias each_line each

  ##
  # Reads lines from the stream which are separated by _eol_.
  #
  # See also #gets

  def readlines(eol=$/)
    ary = []
    while line = self.gets(eol)
      ary << line
    end
    ary
  end

  ##
  # Reads a line from the stream which is separated by _eol_.
  #
  # Raises EOFError if at end of file.

  def readline(eol=$/)
    raise EOFError if eof?
    gets(eol)
  end

  ##
  # Reads one character from the stream.  Returns nil if called at end of
  # file.

  def getc
    read(1)
  end

  ##
  # Calls the given block once for each byte in the stream.

  def each_byte # :yields: byte
    while c = getc
      yield(c.ord)
    end
  end

  ##
  # Reads a one-character string from the stream.  Raises an EOFError at end
  # of file.

  def readchar
    raise EOFError if eof?
    getc
  end

  ##
  # Pushes character _c_ back onto the stream such that a subsequent buffered
  # character read will return it.
  #
  # Unlike IO#getc multiple bytes may be pushed back onto the stream.
  #
  # Has no effect on unbuffered reads (such as #sysread).

  def ungetc(c)
    @rbuffer[0,0] = c.chr
  end

  ##
  # Returns true if the stream is at file which means there is no more data to
  # be read.

  def eof?
    fill_rbuff if !@eof && @rbuffer.empty?
    @eof && @rbuffer.empty?
  end
  alias eof eof?

  #
  # for writing.
  #
  private

  ##
  # Writes _s_ to the buffer.  When the buffer is full or #sync is true the
  # buffer is flushed to the underlying socket.

  def do_write(s)
    @wbuffer = Buffer.new unless defined? @wbuffer
    @wbuffer << s
    @wbuffer.force_encoding(Encoding::BINARY)
    @sync ||= false
    if @sync or @wbuffer.size > BLOCK_SIZE
      until @wbuffer.empty?
        begin
          nwrote = syswrite(@wbuffer)
        rescue Errno::EAGAIN
          retry
        end
        @wbuffer[0, nwrote] = ""
      end
    end
  end

  public

  ##
  # Writes _s_ to the stream.  If the argument is not a String it will be
  # converted using +.to_s+ method.  Returns the number of bytes written.

  def write(*s)
    s.inject(0) do |written, str|
      do_write(str)
      written + str.bytesize
    end
  end

  ##
  # Writes _s_ in the non-blocking manner.
  #
  # If there is buffered data, it is flushed first.  This may block.
  #
  # write_nonblock returns number of bytes written to the SSL connection.
  #
  # When no data can be written without blocking it raises
  # OpenSSL::SSL::SSLError extended by IO::WaitReadable or IO::WaitWritable.
  #
  # IO::WaitReadable means SSL needs to read internally so write_nonblock
  # should be called again after the underlying IO is readable.
  #
  # IO::WaitWritable means SSL needs to write internally so write_nonblock
  # should be called again after underlying IO is writable.
  #
  # So OpenSSL::Buffering#write_nonblock needs two rescue clause as follows.
  #
  #   # emulates blocking write.
  #   begin
  #     result = ssl.write_nonblock(str)
  #   rescue IO::WaitReadable
  #     IO.select([io])
  #     retry
  #   rescue IO::WaitWritable
  #     IO.select(nil, [io])
  #     retry
  #   end
  #
  # Note that one reason that write_nonblock reads from the underlying IO
  # is when the peer requests a new TLS/SSL handshake.  See the openssl FAQ
  # for more details.  http://www.openssl.org/support/faq.html
  #
  # By specifying a keyword argument _exception_ to +false+, you can indicate
  # that write_nonblock should not raise an IO::Wait*able exception, but
  # return the symbol +:wait_writable+ or +:wait_readable+ instead.

  def write_nonblock(s, exception: true)
    flush
    syswrite_nonblock(s, exception: exception)
  end

  ##
  # Writes _s_ to the stream.  _s_ will be converted to a String using
  # +.to_s+ method.

  def <<(s)
    do_write(s)
    self
  end

  ##
  # Writes _args_ to the stream along with a record separator.
  #
  # See IO#puts for full details.

  def puts(*args)
    s = Buffer.new
    if args.empty?
      s << "\n"
    end
    args.each{|arg|
      s << arg.to_s
      s.sub!(/(?<!\n)\z/, "\n")
    }
    do_write(s)
    nil
  end

  ##
  # Writes _args_ to the stream.
  #
  # See IO#print for full details.

  def print(*args)
    s = Buffer.new
    args.each{ |arg| s << arg.to_s }
    do_write(s)
    nil
  end

  ##
  # Formats and writes to the stream converting parameters under control of
  # the format string.
  #
  # See Kernel#sprintf for format string details.

  def printf(s, *args)
    do_write(s % args)
    nil
  end

  ##
  # Flushes buffered data to the SSLSocket.

  def flush
    osync = @sync
    @sync = true
    do_write ""
    return self
  ensure
    @sync = osync
  end

  ##
  # Closes the SSLSocket and flushes any unwritten data.

  def close
    flush rescue nil
    sysclose
  end
end
