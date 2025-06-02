# frozen_string_literal: true
##
# Supports reading and writing gems from/to a generic IO object.  This is
# useful for other applications built on top of rubygems, such as
# rubygems.org.
#
# This is a private class, do not depend on it directly. Instead, pass an IO
# object to `Gem::Package.new`.

class Gem::Package::IOSource < Gem::Package::Source # :nodoc: all
  attr_reader :io

  def initialize(io)
    @io = io
  end

  def start
    @start ||= begin
      if io.pos > 0
        raise Gem::Package::Error, "Cannot read start unless IO is at start"
      end

      value = io.read 20
      io.rewind
      value
    end
  end

  def present?
    true
  end

  def with_read_io
    yield io
  ensure
    io.rewind
  end

  def with_write_io
    yield io
  ensure
    io.rewind
  end

  def path
  end
end
