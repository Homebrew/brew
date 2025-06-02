# frozen_string_literal: true
#--
# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt for additional licensing information.
#++

##
# TarReader reads tar files and allows iteration over their items

class Gem::Package::TarReader
  include Enumerable

  ##
  # Raised if the tar IO is not seekable

  class UnexpectedEOF < StandardError; end

  ##
  # Creates a new TarReader on +io+ and yields it to the block, if given.

  def self.new(io)
    reader = super

    return reader unless block_given?

    begin
      yield reader
    ensure
      reader.close
    end

    nil
  end

  ##
  # Creates a new tar file reader on +io+ which needs to respond to #pos,
  # #eof?, #read, #getc and #pos=

  def initialize(io)
    @io = io
    @init_pos = io.pos
  end

  ##
  # Close the tar file

  def close
  end

  ##
  # Iterates over files in the tarball yielding each entry

  def each
    return enum_for __method__ unless block_given?

    use_seek = @io.respond_to?(:seek)

    until @io.eof? do
      header = Gem::Package::TarHeader.from @io
      return if header.empty?

      entry = Gem::Package::TarReader::Entry.new header, @io
      size = entry.header.size

      yield entry

      skip = (512 - (size % 512)) % 512
      pending = size - entry.bytes_read

      if use_seek
        begin
          # avoid reading if the @io supports seeking
          @io.seek pending, IO::SEEK_CUR
          pending = 0
        rescue Errno::EINVAL
        end
      end

      # if seeking isn't supported or failed
      while pending > 0 do
        bytes_read = @io.read([pending, 4096].min).size
        raise UnexpectedEOF if @io.eof?
        pending -= bytes_read
      end

      @io.read skip # discard trailing zeros

      # make sure nobody can use #read, #getc or #rewind anymore
      entry.close
    end
  end

  alias each_entry each

  ##
  # NOTE: Do not call #rewind during #each

  def rewind
    if @init_pos == 0
      @io.rewind
    else
      @io.pos = @init_pos
    end
  end

  ##
  # Seeks through the tar file until it finds the +entry+ with +name+ and
  # yields it.  Rewinds the tar file to the beginning when the block
  # terminates.

  def seek(name) # :yields: entry
    found = find do |entry|
      entry.full_name == name
    end

    return unless found

    return yield found
  ensure
    rewind
  end
end

require_relative "tar_reader/entry"
