# frozen_string_literal: true

# rubocop:disable Style/AsciiComments

# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt for additional licensing information.

# rubocop:enable Style/AsciiComments

require_relative "security"
require_relative "user_interaction"

##
# Example using a Gem::Package
#
# Builds a .gem file given a Gem::Specification. A .gem file is a tarball
# which contains a data.tar.gz, metadata.gz, checksums.yaml.gz and possibly
# signatures.
#
#   require 'rubygems'
#   require 'rubygems/package'
#
#   spec = Gem::Specification.new do |s|
#     s.summary = "Ruby based make-like utility."
#     s.name = 'rake'
#     s.version = PKG_VERSION
#     s.requirements << 'none'
#     s.files = PKG_FILES
#     s.description = <<-EOF
#   Rake is a Make-like program implemented in Ruby. Tasks
#   and dependencies are specified in standard Ruby syntax.
#     EOF
#   end
#
#   Gem::Package.build spec
#
# Reads a .gem file.
#
#   require 'rubygems'
#   require 'rubygems/package'
#
#   the_gem = Gem::Package.new(path_to_dot_gem)
#   the_gem.contents # get the files in the gem
#   the_gem.extract_files destination_directory # extract the gem into a directory
#   the_gem.spec # get the spec out of the gem
#   the_gem.verify # check the gem is OK (contains valid gem specification, contains a not corrupt contents archive)
#
# #files are the files in the .gem tar file, not the Ruby files in the gem
# #extract_files and #contents automatically call #verify

class Gem::Package
  include Gem::UserInteraction

  class Error < Gem::Exception; end

  class FormatError < Error
    attr_reader :path

    def initialize(message, source = nil)
      if source
        @path = source.is_a?(String) ? source : source.path

        message += " in #{path}" if path
      end

      super message
    end
  end

  class PathError < Error
    def initialize(destination, destination_dir)
      super format("installing into parent path %s of %s is not allowed", destination, destination_dir)
    end
  end

  class SymlinkError < Error
    def initialize(name, destination, destination_dir)
      super format("installing symlink '%s' pointing to parent path %s of %s is not allowed", name, destination, destination_dir)
    end
  end

  class NonSeekableIO < Error; end

  class TooLongFileName < Error; end

  ##
  # Raised when a tar file is corrupt

  class TarInvalidError < Error; end

  attr_accessor :build_time # :nodoc:

  ##
  # Checksums for the contents of the package

  attr_reader :checksums

  ##
  # The files in this package.  This is not the contents of the gem, just the
  # files in the top-level container.

  attr_reader :files

  ##
  # Reference to the gem being packaged.

  attr_reader :gem

  ##
  # The security policy used for verifying the contents of this package.

  attr_accessor :security_policy

  ##
  # Sets the Gem::Specification to use to build this package.

  attr_writer :spec

  ##
  # Permission for directories
  attr_accessor :dir_mode

  ##
  # Permission for program files
  attr_accessor :prog_mode

  ##
  # Permission for other files
  attr_accessor :data_mode

  def self.build(spec, skip_validation = false, strict_validation = false, file_name = nil)
    gem_file = file_name || spec.file_name

    package = new gem_file
    package.spec = spec
    package.build skip_validation, strict_validation

    gem_file
  end

  ##
  # Creates a new Gem::Package for the file at +gem+. +gem+ can also be
  # provided as an IO object.
  #
  # If +gem+ is an existing file in the old format a Gem::Package::Old will be
  # returned.

  def self.new(gem, security_policy = nil)
    gem = if gem.is_a?(Gem::Package::Source)
      gem
    elsif gem.respond_to? :read
      Gem::Package::IOSource.new gem
    else
      Gem::Package::FileSource.new gem
    end

    return super unless self == Gem::Package
    return super unless gem.present?

    return super unless gem.start
    return super unless gem.start.include? "MD5SUM ="

    Gem::Package::Old.new gem
  end

  ##
  # Extracts the Gem::Specification and raw metadata from the .gem file at
  # +path+.
  #--

  def self.raw_spec(path, security_policy = nil)
    format = new(path, security_policy)
    spec = format.spec

    metadata = nil

    File.open path, Gem.binary_mode do |io|
      tar = Gem::Package::TarReader.new io
      tar.each_entry do |entry|
        case entry.full_name
        when "metadata" then
          metadata = entry.read
        when "metadata.gz" then
          metadata = Gem::Util.gunzip entry.read
        end
      end
    end

    [spec, metadata]
  end

  ##
  # Creates a new package that will read or write to the file +gem+.

  def initialize(gem, security_policy) # :notnew:
    require "zlib"

    @gem = gem

    @build_time      = Gem.source_date_epoch
    @checksums       = {}
    @contents        = nil
    @digests         = Hash.new {|h, algorithm| h[algorithm] = {} }
    @files           = nil
    @security_policy = security_policy
    @signatures      = {}
    @signer          = nil
    @spec            = nil
  end

  ##
  # Copies this package to +path+ (if possible)

  def copy_to(path)
    FileUtils.cp @gem.path, path unless File.exist? path
  end

  ##
  # Adds a checksum for each entry in the gem to checksums.yaml.gz.

  def add_checksums(tar)
    Gem.load_yaml

    checksums_by_algorithm = Hash.new {|h, algorithm| h[algorithm] = {} }

    @checksums.each do |name, digests|
      digests.each do |algorithm, digest|
        checksums_by_algorithm[algorithm][name] = digest.hexdigest
      end
    end

    tar.add_file_signed "checksums.yaml.gz", 0o444, @signer do |io|
      gzip_to io do |gz_io|
        Psych.dump checksums_by_algorithm, gz_io
      end
    end
  end

  ##
  # Adds the files listed in the packages's Gem::Specification to data.tar.gz
  # and adds this file to the +tar+.

  def add_contents(tar) # :nodoc:
    digests = tar.add_file_signed "data.tar.gz", 0o444, @signer do |io|
      gzip_to io do |gz_io|
        Gem::Package::TarWriter.new gz_io do |data_tar|
          add_files data_tar
        end
      end
    end

    @checksums["data.tar.gz"] = digests
  end

  ##
  # Adds files included the package's Gem::Specification to the +tar+ file

  def add_files(tar) # :nodoc:
    @spec.files.each do |file|
      stat = File.lstat file

      if stat.symlink?
        tar.add_symlink file, File.readlink(file), stat.mode
      end

      next unless stat.file?

      tar.add_file_simple file, stat.mode, stat.size do |dst_io|
        File.open file, "rb" do |src_io|
          copy_stream(src_io, dst_io)
        end
      end
    end
  end

  ##
  # Adds the package's Gem::Specification to the +tar+ file

  def add_metadata(tar) # :nodoc:
    digests = tar.add_file_signed "metadata.gz", 0o444, @signer do |io|
      gzip_to io do |gz_io|
        gz_io.write @spec.to_yaml
      end
    end

    @checksums["metadata.gz"] = digests
  end

  ##
  # Builds this package based on the specification set by #spec=

  def build(skip_validation = false, strict_validation = false)
    raise ArgumentError, "skip_validation = true and strict_validation = true are incompatible" if skip_validation && strict_validation

    Gem.load_yaml

    @spec.validate true, strict_validation unless skip_validation

    setup_signer(
      signer_options: {
        expiration_length_days: Gem.configuration.cert_expiration_length_days,
      }
    )

    @gem.with_write_io do |gem_io|
      Gem::Package::TarWriter.new gem_io do |gem|
        add_metadata gem
        add_contents gem
        add_checksums gem
      end
    end

    say <<-EOM
  Successfully built RubyGem
  Name: #{@spec.name}
  Version: #{@spec.version}
  File: #{File.basename @gem.path}
EOM
  ensure
    @signer = nil
  end

  ##
  # A list of file names contained in this gem

  def contents
    return @contents if @contents

    verify unless @spec

    @contents = []

    @gem.with_read_io do |io|
      gem_tar = Gem::Package::TarReader.new io

      gem_tar.each do |entry|
        next unless entry.full_name == "data.tar.gz"

        open_tar_gz entry do |pkg_tar|
          pkg_tar.each do |contents_entry|
            @contents << contents_entry.full_name
          end
        end

        return @contents
      end
    end
  rescue Zlib::GzipFile::Error, EOFError, Gem::Package::TarInvalidError => e
    raise Gem::Package::FormatError.new e.message, @gem
  end

  ##
  # Creates a digest of the TarEntry +entry+ from the digest algorithm set by
  # the security policy.

  def digest(entry) # :nodoc:
    algorithms = if @checksums
      @checksums.to_h {|algorithm, _| [algorithm, Gem::Security.create_digest(algorithm)] }
    elsif Gem::Security::DIGEST_NAME
      { Gem::Security::DIGEST_NAME => Gem::Security.create_digest(Gem::Security::DIGEST_NAME) }
    end

    return @digests if algorithms.nil? || algorithms.empty?

    buf = String.new(capacity: 16_384, encoding: Encoding::BINARY)
    until entry.eof?
      entry.readpartial(16_384, buf)
      algorithms.each_value {|digester| digester << buf }
    end
    entry.rewind

    algorithms.each do |algorithm, digester|
      @digests[algorithm][entry.full_name] = digester
    end

    @digests
  end

  ##
  # Extracts the files in this package into +destination_dir+
  #
  # If +pattern+ is specified, only entries matching that glob will be
  # extracted.

  def extract_files(destination_dir, pattern = "*")
    verify unless @spec

    FileUtils.mkdir_p destination_dir, mode: dir_mode && 0o755

    @gem.with_read_io do |io|
      reader = Gem::Package::TarReader.new io

      reader.each do |entry|
        next unless entry.full_name == "data.tar.gz"

        extract_tar_gz entry, destination_dir, pattern

        break # ignore further entries
      end
    end
  rescue Zlib::GzipFile::Error, EOFError, Gem::Package::TarInvalidError => e
    raise Gem::Package::FormatError.new e.message, @gem
  end

  ##
  # Extracts all the files in the gzipped tar archive +io+ into
  # +destination_dir+.
  #
  # If an entry in the archive contains a relative path above
  # +destination_dir+ or an absolute path is encountered an exception is
  # raised.
  #
  # If +pattern+ is specified, only entries matching that glob will be
  # extracted.

  def extract_tar_gz(io, destination_dir, pattern = "*") # :nodoc:
    destination_dir = File.realpath(destination_dir)

    directories = []
    symlinks = []

    open_tar_gz io do |tar|
      tar.each do |entry|
        full_name = entry.full_name
        next unless File.fnmatch pattern, full_name, File::FNM_DOTMATCH

        destination = install_location full_name, destination_dir

        if entry.symlink?
          link_target = entry.header.linkname
          real_destination = link_target.start_with?("/") ? link_target : File.expand_path(link_target, File.dirname(destination))

          raise Gem::Package::SymlinkError.new(full_name, real_destination, destination_dir) unless
            normalize_path(real_destination).start_with? normalize_path(destination_dir + "/")

          symlinks << [full_name, link_target, destination, real_destination]
        end

        FileUtils.rm_rf destination

        mkdir =
          if entry.directory?
            destination
          else
            File.dirname destination
          end

        unless directories.include?(mkdir)
          FileUtils.mkdir_p mkdir, mode: dir_mode ? 0o755 : (entry.header.mode if entry.directory?)
          directories << mkdir
        end

        if entry.file?
          File.open(destination, "wb") {|out| copy_stream(entry, out) }
          FileUtils.chmod file_mode(entry.header.mode) & ~File.umask, destination
        end

        verbose destination
      end
    end

    symlinks.each do |name, target, destination, real_destination|
      if File.exist?(real_destination)
        File.symlink(target, destination)
      else
        alert_warning "#{@spec.full_name} ships with a dangling symlink named #{name} pointing to missing #{target} file. Ignoring"
      end
    end

    if dir_mode
      File.chmod(dir_mode, *directories)
    end
  end

  def file_mode(mode) # :nodoc:
    ((mode & 0o111).zero? ? data_mode : prog_mode) ||
      # If we're not using one of the default modes, then we're going to fall
      # back to the mode from the tarball. In this case we need to mask it down
      # to fit into 2^16 bits (the maximum value for a mode in CRuby since it
      # gets put into an unsigned short).
      (mode & ((1 << 16) - 1))
  end

  ##
  # Gzips content written to +gz_io+ to +io+.
  #--
  # Also sets the gzip modification time to the package build time to ease
  # testing.

  def gzip_to(io) # :yields: gz_io
    gz_io = Zlib::GzipWriter.new io, Zlib::BEST_COMPRESSION
    gz_io.mtime = @build_time

    yield gz_io
  ensure
    gz_io.close
  end

  ##
  # Returns the full path for installing +filename+.
  #
  # If +filename+ is not inside +destination_dir+ an exception is raised.

  def install_location(filename, destination_dir) # :nodoc:
    raise Gem::Package::PathError.new(filename, destination_dir) if
      filename.start_with? "/"

    destination_dir = File.realpath(destination_dir)
    destination = File.expand_path(filename, destination_dir)

    raise Gem::Package::PathError.new(destination, destination_dir) unless
      normalize_path(destination).start_with? normalize_path(destination_dir + "/")

    destination
  end

  def normalize_path(pathname)
    if Gem.win_platform?
      pathname.downcase
    else
      pathname
    end
  end

  ##
  # Loads a Gem::Specification from the TarEntry +entry+

  def load_spec(entry) # :nodoc:
    limit = 10 * 1024 * 1024
    case entry.full_name
    when "metadata" then
      @spec = Gem::Specification.from_yaml limit_read(entry, "metadata", limit)
    when "metadata.gz" then
      Zlib::GzipReader.wrap(entry, external_encoding: Encoding::UTF_8) do |gzio|
        @spec = Gem::Specification.from_yaml limit_read(gzio, "metadata.gz", limit)
      end
    end
  end

  ##
  # Opens +io+ as a gzipped tar archive

  def open_tar_gz(io) # :nodoc:
    Zlib::GzipReader.wrap io do |gzio|
      tar = Gem::Package::TarReader.new gzio

      yield tar
    end
  end

  ##
  # Reads and loads checksums.yaml.gz from the tar file +gem+

  def read_checksums(gem)
    Gem.load_yaml

    @checksums = gem.seek "checksums.yaml.gz" do |entry|
      Zlib::GzipReader.wrap entry do |gz_io|
        Gem::SafeYAML.safe_load limit_read(gz_io, "checksums.yaml.gz", 10 * 1024 * 1024)
      end
    end
  end

  ##
  # Prepares the gem for signing and checksum generation.  If a signing
  # certificate and key are not present only checksum generation is set up.

  def setup_signer(signer_options: {})
    passphrase = ENV["GEM_PRIVATE_KEY_PASSPHRASE"]
    if @spec.signing_key
      @signer =
        Gem::Security::Signer.new(
          @spec.signing_key,
          @spec.cert_chain,
          passphrase,
          signer_options
        )

      @spec.signing_key = nil
      @spec.cert_chain = @signer.cert_chain.map(&:to_s)
    else
      @signer = Gem::Security::Signer.new nil, nil, passphrase
      @spec.cert_chain = @signer.cert_chain.map(&:to_pem) if
        @signer.cert_chain
    end
  end

  ##
  # The spec for this gem.
  #
  # If this is a package for a built gem the spec is loaded from the
  # gem and returned.  If this is a package for a gem being built the provided
  # spec is returned.

  def spec
    verify unless @spec

    @spec
  end

  ##
  # Verifies that this gem:
  #
  # * Contains a valid gem specification
  # * Contains a contents archive
  # * The contents archive is not corrupt
  #
  # After verification the gem specification from the gem is available from
  # #spec

  def verify
    @files     = []
    @spec      = nil

    @gem.with_read_io do |io|
      Gem::Package::TarReader.new io do |reader|
        read_checksums reader

        verify_files reader
      end
    end

    verify_checksums @digests, @checksums

    @security_policy&.verify_signatures @spec, @digests, @signatures

    true
  rescue Gem::Security::Exception
    @spec = nil
    @files = []
    raise
  rescue Errno::ENOENT => e
    raise Gem::Package::FormatError.new e.message
  rescue Zlib::GzipFile::Error, EOFError, Gem::Package::TarInvalidError => e
    raise Gem::Package::FormatError.new e.message, @gem
  end

  ##
  # Verifies the +checksums+ against the +digests+.  This check is not
  # cryptographically secure.  Missing checksums are ignored.

  def verify_checksums(digests, checksums) # :nodoc:
    return unless checksums

    checksums.sort.each do |algorithm, gem_digests|
      gem_digests.sort.each do |file_name, gem_hexdigest|
        computed_digest = digests[algorithm][file_name]

        unless computed_digest.hexdigest == gem_hexdigest
          raise Gem::Package::FormatError.new \
            "#{algorithm} checksum mismatch for #{file_name}", @gem
        end
      end
    end
  end

  ##
  # Verifies +entry+ in a .gem file.

  def verify_entry(entry)
    file_name = entry.full_name
    @files << file_name

    case file_name
    when /\.sig$/ then
      @signatures[$`] = limit_read(entry, file_name, 1024 * 1024) if @security_policy
      return
    else
      digest entry
    end

    case file_name
    when "metadata", "metadata.gz" then
      load_spec entry
    when "data.tar.gz" then
      verify_gz entry
    end
  rescue StandardError
    warn "Exception while verifying #{@gem.path}"
    raise
  end

  ##
  # Verifies the files of the +gem+

  def verify_files(gem)
    gem.each do |entry|
      verify_entry entry
    end

    unless @spec
      raise Gem::Package::FormatError.new "package metadata is missing", @gem
    end

    unless @files.include? "data.tar.gz"
      raise Gem::Package::FormatError.new \
        "package content (data.tar.gz) is missing", @gem
    end

    if (duplicates = @files.group_by {|f| f }.select {|_k,v| v.size > 1 }.map(&:first)) && duplicates.any?
      raise Gem::Security::Exception, "duplicate files in the package: (#{duplicates.map(&:inspect).join(", ")})"
    end
  end

  ##
  # Verifies that +entry+ is a valid gzipped file.

  def verify_gz(entry) # :nodoc:
    Zlib::GzipReader.wrap entry do |gzio|
      # TODO: read into a buffer once zlib supports it
      gzio.read 16_384 until gzio.eof? # gzip checksum verification
    end
  rescue Zlib::GzipFile::Error => e
    raise Gem::Package::FormatError.new(e.message, entry.full_name)
  end

  if RUBY_ENGINE == "truffleruby"
    def copy_stream(src, dst) # :nodoc:
      dst.write src.read
    end
  else
    def copy_stream(src, dst) # :nodoc:
      IO.copy_stream(src, dst)
    end
  end

  def limit_read(io, name, limit)
    bytes = io.read(limit + 1)
    raise Gem::Package::FormatError, "#{name} is too big (over #{limit} bytes)" if bytes.size > limit
    bytes
  end
end

require_relative "package/digest_io"
require_relative "package/source"
require_relative "package/file_source"
require_relative "package/io_source"
require_relative "package/old"
require_relative "package/tar_header"
require_relative "package/tar_reader"
require_relative "package/tar_reader/entry"
require_relative "package/tar_writer"
