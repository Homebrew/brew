# frozen_string_literal: true
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

##
# The format class knows the guts of the ancient .gem file format and provides
# the capability to read such ancient gems.
#
# Please pretend this doesn't exist.

class Gem::Package::Old < Gem::Package
  undef_method :spec=

  ##
  # Creates a new old-format package reader for +gem+.  Old-format packages
  # cannot be written.

  def initialize(gem, security_policy)
    require "fileutils"
    require "zlib"
    Gem.load_yaml

    @contents        = nil
    @gem             = gem
    @security_policy = security_policy
    @spec            = nil
  end

  ##
  # A list of file names contained in this gem

  def contents
    verify

    return @contents if @contents

    @gem.with_read_io do |io|
      read_until_dashes io # spec
      header = file_list io

      @contents = header.map {|file| file["path"] }
    end
  end

  ##
  # Extracts the files in this package into +destination_dir+

  def extract_files(destination_dir)
    verify

    errstr = "Error reading files from gem"

    @gem.with_read_io do |io|
      read_until_dashes io # spec
      header = file_list io
      raise Gem::Exception, errstr unless header

      header.each do |entry|
        full_name = entry["path"]

        destination = install_location full_name, destination_dir

        file_data = String.new

        read_until_dashes io do |line|
          file_data << line
        end

        file_data = file_data.strip.unpack("m")[0]
        file_data = Zlib::Inflate.inflate file_data

        raise Gem::Package::FormatError, "#{full_name} in #{@gem} is corrupt" if
          file_data.length != entry["size"].to_i

        FileUtils.rm_rf destination

        FileUtils.mkdir_p File.dirname(destination), :mode => dir_mode && 0755

        File.open destination, "wb", file_mode(entry["mode"]) do |out|
          out.write file_data
        end

        verbose destination
      end
    end
  rescue Zlib::DataError
    raise Gem::Exception, errstr
  end

  ##
  # Reads the file list section from the old-format gem +io+

  def file_list(io) # :nodoc:
    header = String.new

    read_until_dashes io do |line|
      header << line
    end

    Gem::SafeYAML.safe_load header
  end

  ##
  # Reads lines until a "---" separator is found

  def read_until_dashes(io) # :nodoc:
    while (line = io.gets) && line.chomp.strip != "---" do
      yield line if block_given?
    end
  end

  ##
  # Skips the Ruby self-install header in +io+.

  def skip_ruby(io) # :nodoc:
    loop do
      line = io.gets

      return if line.chomp == "__END__"
      break unless line
    end

    raise Gem::Exception, "Failed to find end of Ruby script while reading gem"
  end

  ##
  # The specification for this gem

  def spec
    verify

    return @spec if @spec

    yaml = String.new

    @gem.with_read_io do |io|
      skip_ruby io
      read_until_dashes io do |line|
        yaml << line
      end
    end

    begin
      @spec = Gem::Specification.from_yaml yaml
    rescue Psych::SyntaxError
      raise Gem::Exception, "Failed to parse gem specification out of gem file"
    end
  rescue ArgumentError
    raise Gem::Exception, "Failed to parse gem specification out of gem file"
  end

  ##
  # Raises an exception if a security policy that verifies data is active.
  # Old format gems cannot be verified as signed.

  def verify
    return true unless @security_policy

    raise Gem::Security::Exception,
          "old format gems do not contain signatures and cannot be verified" if
      @security_policy.verify_data

    true
  end
end
