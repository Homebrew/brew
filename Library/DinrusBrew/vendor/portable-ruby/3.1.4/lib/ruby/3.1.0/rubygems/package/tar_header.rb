# frozen_string_literal: true
#--
# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt for additional licensing information.
#++

##
#--
# struct tarfile_entry_posix {
#   char name[100];     # ASCII + (Z unless filled)
#   char mode[8];       # 0 padded, octal, null
#   char uid[8];        # ditto
#   char gid[8];        # ditto
#   char size[12];      # 0 padded, octal, null
#   char mtime[12];     # 0 padded, octal, null
#   char checksum[8];   # 0 padded, octal, null, space
#   char typeflag[1];   # file: "0"  dir: "5"
#   char linkname[100]; # ASCII + (Z unless filled)
#   char magic[6];      # "ustar\0"
#   char version[2];    # "00"
#   char uname[32];     # ASCIIZ
#   char gname[32];     # ASCIIZ
#   char devmajor[8];   # 0 padded, octal, null
#   char devminor[8];   # o padded, octal, null
#   char prefix[155];   # ASCII + (Z unless filled)
# };
#++
# A header for a tar file

class Gem::Package::TarHeader
  ##
  # Fields in the tar header

  FIELDS = [
    :checksum,
    :devmajor,
    :devminor,
    :gid,
    :gname,
    :linkname,
    :magic,
    :mode,
    :mtime,
    :name,
    :prefix,
    :size,
    :typeflag,
    :uid,
    :uname,
    :version,
  ].freeze

  ##
  # Pack format for a tar header

  PACK_FORMAT = "a100" + # name
                "a8"   + # mode
                "a8"   + # uid
                "a8"   + # gid
                "a12"  + # size
                "a12"  + # mtime
                "a7a"  + # chksum
                "a"    + # typeflag
                "a100" + # linkname
                "a6"   + # magic
                "a2"   + # version
                "a32"  + # uname
                "a32"  + # gname
                "a8"   + # devmajor
                "a8"   + # devminor
                "a155"   # prefix

  ##
  # Unpack format for a tar header

  UNPACK_FORMAT = "A100" + # name
                  "A8"   + # mode
                  "A8"   + # uid
                  "A8"   + # gid
                  "A12"  + # size
                  "A12"  + # mtime
                  "A8"   + # checksum
                  "A"    + # typeflag
                  "A100" + # linkname
                  "A6"   + # magic
                  "A2"   + # version
                  "A32"  + # uname
                  "A32"  + # gname
                  "A8"   + # devmajor
                  "A8"   + # devminor
                  "A155"   # prefix

  attr_reader(*FIELDS)

  EMPTY_HEADER = ("\0" * 512).freeze # :nodoc:

  ##
  # Creates a tar header from IO +stream+

  def self.from(stream)
    header = stream.read 512
    empty = (EMPTY_HEADER == header)

    fields = header.unpack UNPACK_FORMAT

    new :name     => fields.shift,
        :mode     => strict_oct(fields.shift),
        :uid      => oct_or_256based(fields.shift),
        :gid      => oct_or_256based(fields.shift),
        :size     => strict_oct(fields.shift),
        :mtime    => strict_oct(fields.shift),
        :checksum => strict_oct(fields.shift),
        :typeflag => fields.shift,
        :linkname => fields.shift,
        :magic    => fields.shift,
        :version  => strict_oct(fields.shift),
        :uname    => fields.shift,
        :gname    => fields.shift,
        :devmajor => strict_oct(fields.shift),
        :devminor => strict_oct(fields.shift),
        :prefix   => fields.shift,

        :empty => empty
  end

  def self.strict_oct(str)
    return str.strip.oct if str.strip =~ /\A[0-7]*\z/

    raise ArgumentError, "#{str.inspect} is not an octal string"
  end

  def self.oct_or_256based(str)
    # \x80 flags a positive 256-based number
    # \ff flags a negative 256-based number
    # In case we have a match, parse it as a signed binary value
    # in big-endian order, except that the high-order bit is ignored.
    return str.unpack("N2").last if str =~ /\A[\x80\xff]/n
    strict_oct(str)
  end

  ##
  # Creates a new TarHeader using +vals+

  def initialize(vals)
    unless vals[:name] && vals[:size] && vals[:prefix] && vals[:mode]
      raise ArgumentError, ":name, :size, :prefix and :mode required"
    end

    vals[:uid] ||= 0
    vals[:gid] ||= 0
    vals[:mtime] ||= 0
    vals[:checksum] ||= ""
    vals[:typeflag] = "0" if vals[:typeflag].nil? || vals[:typeflag].empty?
    vals[:magic] ||= "ustar"
    vals[:version] ||= "00"
    vals[:uname] ||= "wheel"
    vals[:gname] ||= "wheel"
    vals[:devmajor] ||= 0
    vals[:devminor] ||= 0

    FIELDS.each do |name|
      instance_variable_set "@#{name}", vals[name]
    end

    @empty = vals[:empty]
  end

  ##
  # Is the tar entry empty?

  def empty?
    @empty
  end

  def ==(other) # :nodoc:
    self.class === other &&
      @checksum == other.checksum &&
      @devmajor == other.devmajor &&
      @devminor == other.devminor &&
      @gid      == other.gid      &&
      @gname    == other.gname    &&
      @linkname == other.linkname &&
      @magic    == other.magic    &&
      @mode     == other.mode     &&
      @mtime    == other.mtime    &&
      @name     == other.name     &&
      @prefix   == other.prefix   &&
      @size     == other.size     &&
      @typeflag == other.typeflag &&
      @uid      == other.uid      &&
      @uname    == other.uname    &&
      @version  == other.version
  end

  def to_s # :nodoc:
    update_checksum
    header
  end

  ##
  # Updates the TarHeader's checksum

  def update_checksum
    header = header " " * 8
    @checksum = oct calculate_checksum(header), 6
  end

  private

  def calculate_checksum(header)
    header.unpack("C*").inject {|a, b| a + b }
  end

  def header(checksum = @checksum)
    header = [
      name,
      oct(mode, 7),
      oct(uid, 7),
      oct(gid, 7),
      oct(size, 11),
      oct(mtime, 11),
      checksum,
      " ",
      typeflag,
      linkname,
      magic,
      oct(version, 2),
      uname,
      gname,
      oct(devmajor, 7),
      oct(devminor, 7),
      prefix,
    ]

    header = header.pack PACK_FORMAT

    header << ("\0" * ((512 - header.size) % 512))
  end

  def oct(num, len)
    "%0#{len}o" % num
  end
end
