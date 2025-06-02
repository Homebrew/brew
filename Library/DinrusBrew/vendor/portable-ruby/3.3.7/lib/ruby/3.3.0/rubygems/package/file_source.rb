# frozen_string_literal: true

##
# The primary source of gems is a file on disk, including all usages
# internal to rubygems.
#
# This is a private class, do not depend on it directly. Instead, pass a path
# object to `Gem::Package.new`.

class Gem::Package::FileSource < Gem::Package::Source # :nodoc: all
  attr_reader :path

  def initialize(path)
    @path = path
  end

  def start
    @start ||= File.read path, 20
  end

  def present?
    File.exist? path
  end

  def with_write_io(&block)
    File.open path, "wb", &block
  end

  def with_read_io(&block)
    File.open path, "rb", &block
  end
end
