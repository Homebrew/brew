# typed: strict
# frozen_string_literal: true

require "mktemp"
require "system_command"

# Module containing all available strategies for unpacking archives.
module UnpackStrategy
  extend T::Helpers
  include SystemCommand::Mixin
  abstract!

  requires_ancestor { Kernel }

  UnpackStrategyType = T.type_alias { T.all(T::Class[UnpackStrategy], UnpackStrategy::ClassMethods) }

  module ClassMethods
    extend T::Helpers
    abstract!

    sig { abstract.returns(T::Array[String]) }
    def extensions; end

    sig { abstract.params(path: Pathname).returns(T::Boolean) }
    def can_extract?(path); end
  end

  mixes_in_class_methods(ClassMethods)

  sig { returns(T.nilable(T::Array[UnpackStrategyType])) }
  def self.strategies
    @strategies ||= T.let([
      Tar, # Needs to be before Bzip2/Gzip/Xz/Lzma/Zstd.
      Pax,
      Gzip,
      Dmg, # Needs to be before Bzip2/Xz/Lzma.
      Lzma,
      Xz,
      Zstd,
      Lzip,
      Air, # Needs to be before `Zip`.
      Jar, # Needs to be before `Zip`.
      LuaRock, # Needs to be before `Zip`.
      MicrosoftOfficeXml, # Needs to be before `Zip`.
      Zip,
      Pkg, # Needs to be before `Xar`.
      Xar,
      Ttf,
      Otf,
      Git,
      Mercurial,
      Subversion,
      Cvs,
      SelfExtractingExecutable, # Needs to be before `Cab`.
      Cab,
      Executable,
      Bzip2,
      Fossil,
      Bazaar,
      Compress,
      P7Zip,
      Sit,
      Rar,
      Lha,
    ].freeze, T.nilable(T::Array[UnpackStrategyType]))
  end
  private_class_method :strategies

  sig { params(type: Symbol).returns(T.nilable(UnpackStrategyType)) }
  def self.from_type(type)
    type = {
      naked:     :uncompressed,
      nounzip:   :uncompressed,
      seven_zip: :p7zip,
    }.fetch(type, type)

    begin
      const_get(type.to_s.split("_").map(&:capitalize).join.gsub(/\d+[a-z]/, &:upcase))
    rescue NameError
      nil
    end
  end

  sig { params(extension: String).returns(T.nilable(UnpackStrategyType)) }
  def self.from_extension(extension)
    return unless strategies

    strategies&.sort_by { |s| s.extensions.map(&:length).max || 0 }
              &.reverse
              &.find { |s| s.extensions.any? { |ext| extension.end_with?(ext) } }
  end

  sig { params(path: Pathname).returns(T.nilable(UnpackStrategyType)) }
  def self.from_magic(path)
    strategies&.find { |s| s.can_extract?(path) }
  end

  sig {
    params(path: Pathname, prioritize_extension: T::Boolean, type: T.nilable(Symbol), ref_type: T.nilable(Symbol),
           ref: T.nilable(String), merge_xattrs: T::Boolean).returns(T.untyped)
  }
  def self.detect(path, prioritize_extension: false, type: nil, ref_type: nil, ref: nil, merge_xattrs: false)
    strategy = from_type(type) if type

    if prioritize_extension && path.extname.present?
      strategy ||= from_extension(path.extname)

      strategy ||= strategies&.find { |s| (s < Directory || s == Fossil) && s.can_extract?(path) }
    else
      strategy ||= from_magic(path)
      strategy ||= from_extension(path.extname)
    end

    strategy ||= Uncompressed

    strategy.new(path, ref_type:, ref:, merge_xattrs:)
  end

  sig { returns(Pathname) }
  attr_reader :path

  sig { returns(T::Boolean) }
  attr_reader :merge_xattrs

  sig {
    params(path: T.any(String, Pathname), ref_type: T.nilable(Symbol), ref: T.nilable(String),
           merge_xattrs: T::Boolean).void
  }
  def initialize(path, ref_type: nil, ref: nil, merge_xattrs: false)
    @path = T.let(Pathname(path).expand_path, Pathname)
    @ref_type = T.let(ref_type, T.nilable(Symbol))
    @ref = T.let(ref, T.nilable(String))
    @merge_xattrs = T.let(merge_xattrs, T::Boolean)
  end

  sig { abstract.params(unpack_dir: Pathname, basename: Pathname, verbose: T::Boolean).void }
  def extract_to_dir(unpack_dir, basename:, verbose:); end
  private :extract_to_dir

  sig {
    params(
      to: T.nilable(Pathname), basename: T.nilable(T.any(String, Pathname)), verbose: T::Boolean,
    ).void
  }
  def extract(to: nil, basename: nil, verbose: false)
    basename ||= path.basename
    unpack_dir = Pathname(to || Dir.pwd).expand_path
    unpack_dir.mkpath
    extract_to_dir(unpack_dir, basename: Pathname(basename), verbose:)
  end

  sig {
    params(
      to:                   T.nilable(Pathname),
      basename:             T.nilable(T.any(String, Pathname)),
      verbose:              T::Boolean,
      prioritize_extension: T::Boolean,
    ).returns(T.untyped)
  }
  def extract_nestedly(to: nil, basename: nil, verbose: false, prioritize_extension: false)
    Mktemp.new("homebrew-unpack").run(chdir: false) do |unpack_dir|
      tmp_unpack_dir = T.must(unpack_dir.tmpdir)

      extract(to: tmp_unpack_dir, basename:, verbose:)

      children = tmp_unpack_dir.children

      if children.size == 1 && !children.fetch(0).directory?
        first_child = children.first
        next if first_child.nil?

        s = UnpackStrategy.detect(first_child, prioritize_extension:)

        s.extract_nestedly(to:, verbose:, prioritize_extension:)

        next
      end

      # Ensure all extracted directories are writable.
      each_directory(tmp_unpack_dir) do |path|
        next if path.writable?

        FileUtils.chmod "u+w", path, verbose:
      end

      Directory.new(tmp_unpack_dir, move: true).extract(to:, verbose:)
    end
  end

  sig { returns(T.any(T::Array[Cask::Cask], T::Array[Formula])) }
  def dependencies
    []
  end

  # Helper method for iterating over directory trees.
  sig {
    params(
      pathname: Pathname,
      _block:   T.proc.params(path: Pathname).void,
    ).returns(T.nilable(Pathname))
  }
  def each_directory(pathname, &_block)
    pathname.find do |path|
      yield path if path.directory?
    end
  end
end

require "unpack_strategy/air"
require "unpack_strategy/bazaar"
require "unpack_strategy/bzip2"
require "unpack_strategy/cab"
require "unpack_strategy/compress"
require "unpack_strategy/cvs"
require "unpack_strategy/directory"
require "unpack_strategy/dmg"
require "unpack_strategy/executable"
require "unpack_strategy/fossil"
require "unpack_strategy/generic_unar"
require "unpack_strategy/git"
require "unpack_strategy/gzip"
require "unpack_strategy/jar"
require "unpack_strategy/lha"
require "unpack_strategy/lua_rock"
require "unpack_strategy/lzip"
require "unpack_strategy/lzma"
require "unpack_strategy/mercurial"
require "unpack_strategy/microsoft_office_xml"
require "unpack_strategy/otf"
require "unpack_strategy/p7zip"
require "unpack_strategy/pax"
require "unpack_strategy/pkg"
require "unpack_strategy/rar"
require "unpack_strategy/self_extracting_executable"
require "unpack_strategy/sit"
require "unpack_strategy/subversion"
require "unpack_strategy/tar"
require "unpack_strategy/ttf"
require "unpack_strategy/uncompressed"
require "unpack_strategy/xar"
require "unpack_strategy/xz"
require "unpack_strategy/zip"
require "unpack_strategy/zstd"
