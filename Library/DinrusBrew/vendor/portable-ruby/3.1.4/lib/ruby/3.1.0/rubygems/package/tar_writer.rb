# frozen_string_literal: true
#--
# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt for additional licensing information.
#++

##
# Allows writing of tar files

class Gem::Package::TarWriter
  class FileOverflow < StandardError; end

  ##
  # IO wrapper that allows writing a limited amount of data

  class BoundedStream
    ##
    # Maximum number of bytes that can be written

    attr_reader :limit

    ##
    # Number of bytes written

    attr_reader :written

    ##
    # Wraps +io+ and allows up to +limit+ bytes to be written

    def initialize(io, limit)
      @io = io
      @limit = limit
      @written = 0
    end

    ##
    # Writes +data+ onto the IO, raising a FileOverflow exception if the
    # number of bytes will be more than #limit

    def write(data)
      if data.bytesize + @written > @limit
        raise FileOverflow, "You tried to feed more data than fits in the file."
      end
      @io.write data
      @written += data.bytesize
      data.bytesize
    end
  end

  ##
  # IO wrapper that provides only #write

  class RestrictedStream
    ##
    # Creates a new RestrictedStream wrapping +io+

    def initialize(io)
      @io = io
    end

    ##
    # Writes +data+ onto the IO

    def write(data)
      @io.write data
    end
  end

  ##
  # Creates a new TarWriter, yielding it if a block is given

  def self.new(io)
    writer = super

    return writer unless block_given?

    begin
      yield writer
    ensure
      writer.close
    end

    nil
  end

  ##
  # Creates a new TarWriter that will write to +io+

  def initialize(io)
    @io = io
    @closed = false
  end

  ##
  # Adds file +name+ with permissions +mode+, and yields an IO for writing the
  # file to

  def add_file(name, mode) # :yields: io
    check_closed

    name, prefix = split_name name

    init_pos = @io.pos
    @io.write Gem::Package::TarHeader::EMPTY_HEADER # placeholder for the header

    yield RestrictedStream.new(@io) if block_given?

    size = @io.pos - init_pos - 512

    remainder = (512 - (size % 512)) % 512
    @io.write "\0" * remainder

    final_pos = @io.pos
    @io.pos = init_pos

    header = Gem::Package::TarHeader.new :name => name, :mode => mode,
                                         :size => size, :prefix => prefix,
                                         :mtime => Gem.source_date_epoch

    @io.write header
    @io.pos = final_pos

    self
  end

  ##
  # Adds +name+ with permissions +mode+ to the tar, yielding +io+ for writing
  # the file.  The +digest_algorithm+ is written to a read-only +name+.sum
  # file following the given file contents containing the digest name and
  # hexdigest separated by a tab.
  #
  # The created digest object is returned.

  def add_file_digest(name, mode, digest_algorithms) # :yields: io
    digests = digest_algorithms.map do |digest_algorithm|
      digest = digest_algorithm.new
      digest_name =
        if digest.respond_to? :name
          digest.name
        else
          digest_algorithm.class.name[/::([^:]+)\z/, 1]
        end

      [digest_name, digest]
    end

    digests = Hash[*digests.flatten]

    add_file name, mode do |io|
      Gem::Package::DigestIO.wrap io, digests do |digest_io|
        yield digest_io
      end
    end

    digests
  end

  ##
  # Adds +name+ with permissions +mode+ to the tar, yielding +io+ for writing
  # the file.  The +signer+ is used to add a digest file using its
  # digest_algorithm per add_file_digest and a cryptographic signature in
  # +name+.sig.  If the signer has no key only the checksum file is added.
  #
  # Returns the digest.

  def add_file_signed(name, mode, signer)
    digest_algorithms = [
      signer.digest_algorithm,
      Gem::Security.create_digest("SHA512"),
    ].compact.uniq

    digests = add_file_digest name, mode, digest_algorithms do |io|
      yield io
    end

    signature_digest = digests.values.compact.find do |digest|
      digest_name =
        if digest.respond_to? :name
          digest.name
        else
          digest.class.name[/::([^:]+)\z/, 1]
        end

      digest_name == signer.digest_name
    end

    raise "no #{signer.digest_name} in #{digests.values.compact}" unless signature_digest

    if signer.key
      signature = signer.sign signature_digest.digest

      add_file_simple "#{name}.sig", 0444, signature.length do |io|
        io.write signature
      end
    end

    digests
  end

  ##
  # Add file +name+ with permissions +mode+ +size+ bytes long.  Yields an IO
  # to write the file to.

  def add_file_simple(name, mode, size) # :yields: io
    check_closed

    name, prefix = split_name name

    header = Gem::Package::TarHeader.new(:name => name, :mode => mode,
                                         :size => size, :prefix => prefix,
                                         :mtime => Gem.source_date_epoch).to_s

    @io.write header
    os = BoundedStream.new @io, size

    yield os if block_given?

    min_padding = size - os.written
    @io.write("\0" * min_padding)

    remainder = (512 - (size % 512)) % 512
    @io.write("\0" * remainder)

    self
  end

  ##
  # Adds symlink +name+ with permissions +mode+, linking to +target+.

  def add_symlink(name, target, mode)
    check_closed

    name, prefix = split_name name

    header = Gem::Package::TarHeader.new(:name => name, :mode => mode,
                                         :size => 0, :typeflag => "2",
                                         :linkname => target,
                                         :prefix => prefix,
                                         :mtime => Gem.source_date_epoch).to_s

    @io.write header

    self
  end

  ##
  # Raises IOError if the TarWriter is closed

  def check_closed
    raise IOError, "closed #{self.class}" if closed?
  end

  ##
  # Closes the TarWriter

  def close
    check_closed

    @io.write "\0" * 1024
    flush

    @closed = true
  end

  ##
  # Is the TarWriter closed?

  def closed?
    @closed
  end

  ##
  # Flushes the TarWriter's IO

  def flush
    check_closed

    @io.flush if @io.respond_to? :flush
  end

  ##
  # Creates a new directory in the tar file +name+ with +mode+

  def mkdir(name, mode)
    check_closed

    name, prefix = split_name(name)

    header = Gem::Package::TarHeader.new :name => name, :mode => mode,
                                         :typeflag => "5", :size => 0,
                                         :prefix => prefix,
                                         :mtime => Gem.source_date_epoch

    @io.write header

    self
  end

  ##
  # Splits +name+ into a name and prefix that can fit in the TarHeader

  def split_name(name) # :nodoc:
    if name.bytesize > 256
      raise Gem::Package::TooLongFileName.new("File \"#{name}\" has a too long path (should be 256 or less)")
    end

    prefix = ""
    if name.bytesize > 100
      parts = name.split("/", -1) # parts are never empty here
      name = parts.pop            # initially empty for names with a trailing slash ("foo/.../bar/")
      prefix = parts.join("/")    # if empty, then it's impossible to split (parts is empty too)
      while !parts.empty? && (prefix.bytesize > 155 || name.empty?)
        name = parts.pop + "/" + name
        prefix = parts.join("/")
      end

      if name.bytesize > 100 || prefix.empty?
        raise Gem::Package::TooLongFileName.new("File \"#{prefix}/#{name}\" has a too long name (should be 100 or less)")
      end

      if prefix.bytesize > 155
        raise Gem::Package::TooLongFileName.new("File \"#{prefix}/#{name}\" has a too long base path (should be 155 or less)")
      end
    end

    return name, prefix
  end
end
