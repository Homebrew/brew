# frozen_string_literal: true

# rubocop:disable Style/AsciiComments

# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt for additional licensing information.

# rubocop:enable Style/AsciiComments

##
# TarReader reads tar files and allows iteration over their items

class Gem::Package::TarReader
  include Enumerable

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

    until @io.eof? do
      begin
        header = Gem::Package::TarHeader.from @io
      rescue ArgumentError => e
        # Specialize only exceptions from Gem::Package::TarHeader.strict_oct
        raise e unless e.message.match?(/ is not an octal string$/)
        raise Gem::Package::TarInvalidError, e.message
      end

      return if header.empty?
      entry = Gem::Package::TarReader::Entry.new header, @io
      yield entry
      entry.close
    end
  end

  alias_method :each_entry, :each

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

    yield found
  ensure
    rewind
  end
end

require_relative "tar_reader/entry"
