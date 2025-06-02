# frozen_string_literal: true

# rubocop:disable Style/AsciiComments

# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt for additional licensing information.

# rubocop:enable Style/AsciiComments

##
# Class for reading entries out of a tar file

class Gem::Package::TarReader::Entry
  ##
  # Creates a new tar entry for +header+ that will be read from +io+
  # If a block is given, the entry is yielded and then closed.

  def self.open(header, io, &block)
    entry = new header, io
    return entry unless block_given?
    begin
      yield entry
    ensure
      entry.close
    end
  end

  ##
  # Header for this tar entry

  attr_reader :header

  ##
  # Creates a new tar entry for +header+ that will be read from +io+

  def initialize(header, io)
    @closed = false
    @header = header
    @io = io
    @orig_pos = @io.pos
    @end_pos = @orig_pos + @header.size
    @read = 0
  end

  def check_closed # :nodoc:
    raise IOError, "closed #{self.class}" if closed?
  end

  ##
  # Number of bytes read out of the tar entry

  def bytes_read
    @read
  end

  ##
  # Closes the tar entry

  def close
    return if closed?
    # Seek to the end of the entry if it wasn't fully read
    seek(0, IO::SEEK_END)
    # discard trailing zeros
    skip = (512 - (@header.size % 512)) % 512
    @io.read(skip)
    @closed = true
    nil
  end

  ##
  # Is the tar entry closed?

  def closed?
    @closed
  end

  ##
  # Are we at the end of the tar entry?

  def eof?
    check_closed

    @read >= @header.size
  end

  ##
  # Full name of the tar entry

  def full_name
    if @header.prefix != ""
      File.join @header.prefix, @header.name
    else
      @header.name
    end
  rescue ArgumentError => e
    raise unless e.message == "string contains null byte"
    raise Gem::Package::TarInvalidError,
          "tar is corrupt, name contains null byte"
  end

  ##
  # Read one byte from the tar entry

  def getc
    return nil if eof?

    ret = @io.getc
    @read += 1 if ret

    ret
  end

  ##
  # Is this tar entry a directory?

  def directory?
    @header.typeflag == "5"
  end

  ##
  # Is this tar entry a file?

  def file?
    @header.typeflag == "0"
  end

  ##
  # Is this tar entry a symlink?

  def symlink?
    @header.typeflag == "2"
  end

  ##
  # The position in the tar entry

  def pos
    check_closed

    bytes_read
  end

  ##
  # Seek to the position in the tar entry

  def pos=(new_pos)
    seek(new_pos, IO::SEEK_SET)
  end

  def size
    @header.size
  end

  alias_method :length, :size

  ##
  # Reads +maxlen+ bytes from the tar file entry, or the rest of the entry if nil

  def read(maxlen = nil)
    if eof?
      return maxlen.to_i.zero? ? "" : nil
    end

    max_read = [maxlen, @header.size - @read].compact.min

    ret = @io.read max_read
    if ret.nil?
      return maxlen ? nil : "" # IO.read returns nil on EOF with len argument
    end
    @read += ret.size

    ret
  end

  def readpartial(maxlen, outbuf = "".b)
    if eof? && maxlen > 0
      raise EOFError, "end of file reached"
    end

    max_read = [maxlen, @header.size - @read].min

    @io.readpartial(max_read, outbuf)
    @read += outbuf.size

    outbuf
  end

  ##
  # Seeks to +offset+ bytes into the tar file entry
  # +whence+ can be IO::SEEK_SET, IO::SEEK_CUR, or IO::SEEK_END

  def seek(offset, whence = IO::SEEK_SET)
    check_closed

    new_pos =
      case whence
      when IO::SEEK_SET then @orig_pos + offset
      when IO::SEEK_CUR then @io.pos + offset
      when IO::SEEK_END then @end_pos + offset
      else
        raise ArgumentError, "invalid whence"
      end

    if new_pos < @orig_pos
      new_pos = @orig_pos
    elsif new_pos > @end_pos
      new_pos = @end_pos
    end

    pending = new_pos - @io.pos

    return 0 if pending == 0

    if @io.respond_to?(:seek)
      begin
        # avoid reading if the @io supports seeking
        @io.seek new_pos, IO::SEEK_SET
        pending = 0
      rescue Errno::EINVAL
      end
    end

    # if seeking isn't supported or failed
    # negative seek requires that we rewind and read
    if pending < 0
      @io.rewind
      pending = new_pos
    end

    while pending > 0 do
      size_read = @io.read([pending, 4096].min)&.size
      raise(EOFError, "end of file reached") if size_read.nil?
      pending -= size_read
    end

    @read = @io.pos - @orig_pos

    0
  end

  ##
  # Rewinds to the beginning of the tar file entry

  def rewind
    check_closed
    seek(0, IO::SEEK_SET)
  end
end
