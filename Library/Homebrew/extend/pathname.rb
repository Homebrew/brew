# typed: strict
# frozen_string_literal: true

require "system_command"
require "extend/pathname/disk_usage_extension"
require "extend/pathname/eager_initialize_extension"
require "extend/pathname/observer_pathname_extension"
require "extend/pathname/write_mkpath_extension"
require "utils/output"
require "utils/path"

# Stubs needed to keep Sorbet happy.
# rubocop:disable Style/OneClassPerFile

# {Pathname} extension for dealing with Mach-O files.
module MachOShim; end

# {Pathname} extension for dealing with ELF files.
module ELFShim; end

# @api private
module BinaryPathname
  sig { params(path: T.any(Pathname, String, MachOShim, ELFShim)).returns(T.any(MachOShim, ELFShim)) }
  def self.wrap(path) = raise(NotImplementedError)
end

# Homebrew extends Ruby's `Pathname` to make our code more readable.
# @see https://ruby-doc.org/stdlib-2.6.3/libdoc/pathname/rdoc/Pathname.html Ruby's Pathname API
# TODO: move all of these to other modules e.g. Utils.
class Pathname
  include SystemCommand::Mixin
  include DiskUsageExtension
  include Utils::Output::Mixin
  prepend EagerInitializeExtension

  sig { void }
  def self.activate_extensions!
    Pathname.prepend(WriteMkpathExtension)
  end

  # Moves a file from the original location to the {Pathname}'s.
  #
  # @api public
  sig {
    params(sources: T.any(
      Resource, Resource::Partial, String, Pathname,
      T::Array[T.any(String, Pathname)], T::Hash[T.any(String, Pathname), T.any(String, Pathname)]
    )).void
  }
  def install(*sources)
    sources.each do |src|
      case src
      when Resource
        src.stage(self)
      when Resource::Partial
        src.resource.stage { install(*src.files) }
      when Array
        if src.empty?
          opoo "Tried to install empty array to #{self}"
          break
        end
        src.each { |s| install_p(s, File.basename(s)) }
      when Hash
        if src.empty?
          opoo "Tried to install empty hash to #{self}"
          break
        end
        src.each { |s, new_basename| install_p(s, new_basename) }
      else
        install_p(src, File.basename(src))
      end
    end
  end

  # Creates symlinks to sources in this folder.
  #
  # @api public
  sig {
    params(
      sources: T.any(String, Pathname, T::Array[T.any(String, Pathname)],
                     T::Hash[T.any(String, Pathname), T.any(String, Pathname)]),
    ).void
  }
  def install_symlink(*sources)
    sources.each do |src|
      case src
      when Array
        src.each { |s| install_symlink_p(s, File.basename(s)) }
      when Hash
        src.each { |s, new_basename| install_symlink_p(s, new_basename) }
      else
        install_symlink_p(src, File.basename(src))
      end
    end
  end

  # Only appends to a file that is already created.
  #
  # @api public
  sig { params(content: String, open_args: T.untyped).void }
  def append_lines(content, **open_args)
    raise "Cannot append file that doesn't exist: #{self}" unless exist?

    File.open(self, "a", **open_args) { |f| f.puts(content) }
  end

  # Write to a file atomically.
  #
  # NOTE: This always overwrites.
  #
  # @api public
  sig { params(content: String).void }
  def atomic_write(content)
    require "extend/file/atomic"

    old_stat = stat if exist?
    File.atomic_write(self) do |file|
      file.write(content)
    end

    return unless old_stat

    # Try to restore original file's permissions separately
    # atomic_write does it itself, but it actually erases
    # them if chown fails
    begin
      # Set correct permissions on new file
      chown(old_stat.uid, nil)
      chown(nil, old_stat.gid)
    rescue Errno::EPERM, Errno::EACCES
      # Changing file ownership failed, moving on.
      nil
    end

    begin
      # This operation will affect filesystem ACL's
      chmod(old_stat.mode)
    rescue Errno::EPERM, Errno::EACCES
      # Changing file permissions failed, moving on.
      nil
    end
  end

  sig {
    params(pattern: T.any(Pathname, String, Regexp), replacement: T.any(Pathname, String),
           block: T.nilable(T.proc.params(src: Pathname, dst: Pathname).returns(Pathname))).void
  }
  def cp_path_sub(pattern, replacement, &block)
    Utils::Output.odeprecated "Pathname#cp_path_sub", "Utils::Path.cp_path_sub"
    Utils::Path.cp_path_sub(self, pattern, replacement, &block)
  end

  # Extended to support common double extensions.
  #
  # @api public
  sig { returns(String) }
  def extname
    basename = File.basename(self)

    bottle_ext, = HOMEBREW_BOTTLES_EXTNAME_REGEX.match(basename).to_a
    return bottle_ext if bottle_ext

    archive_ext = basename[/(\.(?:tar|cpio|pax)\.(?:gz|bz2|lz|xz|zst|Z))\Z/, 1]
    return archive_ext if archive_ext

    # Don't treat version numbers as extname.
    return "" if basename.match?(/\b\d+\.\d+[^.]*\Z/) && !basename.end_with?(".7z")

    File.extname(basename)
  end

  # For filetypes we support, returns basename without extension.
  #
  # @api public
  sig { returns(String) }
  def stem
    File.basename(self, extname)
  end

  sig { returns(T::Boolean) }
  def rmdir_if_possible
    Utils::Output.odeprecated "Pathname#rmdir_if_possible", "Utils::Path.rmdir_if_possible"
    Utils::Path.rmdir_if_possible(self)
  end

  sig { returns(Version) }
  def version
    require "version"
    Version.parse(basename)
  end

  sig { returns(T::Boolean) }
  def text_executable?
    Utils::Output.odeprecated "Pathname#text_executable?", "Utils::Path.text_executable?"
    Utils::Path.text_executable?(self)
  end

  sig { returns(String) }
  def sha256
    require "digest/sha2"
    # In integration tests only, raise when an unchanged file is rehashed
    # without the digest cache being involved.
    ::Downloadable::VerificationCache.check_repeated_hashing(self) if defined?(::Downloadable::VerificationCache)
    Digest::SHA256.file(self).hexdigest
  end

  sig { params(expected: T.nilable(Checksum)).void }
  def verify_checksum(expected)
    raise ChecksumMissingError if expected.blank?

    actual = Checksum.new(sha256.downcase)
    raise ChecksumMismatchError.new(self, expected, actual) if expected != actual
  end

  alias to_str to_s

  # Change to this directory, optionally executing the given block.
  #
  # @api public
  sig {
    type_parameters(:U).params(
      _block: T.proc.params(path: Pathname).returns(T.type_parameter(:U)),
    ).returns(T.type_parameter(:U))
  }
  def cd(&_block)
    Dir.chdir(self) { yield self }
  end

  # Get all sub-directories of this directory.
  #
  # @api public
  sig { returns(T::Array[Pathname]) }
  def subdirs
    children.select(&:directory?)
  end

  sig { returns(Pathname) }
  def resolved_path
    Utils::Output.odeprecated "Pathname#resolved_path", "Utils::Path.resolved_path"
    Utils::Path.resolved_path(self)
  end

  sig { returns(T::Boolean) }
  def resolved_path_exists?
    Utils::Output.odeprecated "Pathname#resolved_path_exists?", "Utils::Path.resolved_path_exists?"
    Utils::Path.resolved_path_exists?(self)
  end

  sig { params(src: Pathname).void }
  def make_relative_symlink(src)
    dirname.mkpath
    File.symlink(src.relative_path_from(dirname), self)
  end

  sig { params(block: T.proc.void).void }
  def ensure_writable(&block)
    Utils::Output.odeprecated "Pathname#ensure_writable", "Utils::Path.ensure_writable"
    Utils::Path.ensure_writable(self, &block)
  end

  sig { void }
  def install_info
    Utils::Output.odeprecated "Pathname#install_info", "Utils::Path.install_info"
    Utils::Path.install_info(self)
  end

  sig { void }
  def uninstall_info
    Utils::Output.odeprecated "Pathname#uninstall_info", "Utils::Path.uninstall_info"
    Utils::Path.uninstall_info(self)
  end

  # Writes an exec script in this folder for each target pathname.
  #
  # @api public
  sig { params(targets: T.any(T::Array[T.any(String, Pathname)], String, Pathname)).void }
  def write_exec_script(*targets)
    targets.flatten!
    if targets.empty?
      opoo "Tried to write exec scripts to #{self} for an empty list of targets"
      return
    end
    mkpath
    targets.each do |target|
      target = Pathname.new(target) # allow pathnames or strings
      join(target.basename).write <<~SH
        #!/bin/bash
        exec "#{target}" "$@"
      SH
    end
  end

  # Writes an exec script that sets environment variables.
  #
  # @api public
  sig {
    params(
      target:      T.any(Pathname, String),
      args_or_env: T.any(
        String, Pathname,
        T::Array[T.any(String, Pathname)],
        T::Hash[T.any(String, Symbol), T.any(String, Pathname)]
      ),
      env:         T.nilable(T::Hash[T.any(String, Symbol), T.any(String, Pathname)]),
    ).void
  }
  def write_env_script(target, args_or_env, env = nil)
    args = if env.nil?
      raise ArgumentError, "#{args_or_env.inspect} is not a Hash" unless args_or_env.is_a?(Hash)

      env = args_or_env
      nil
    elsif args_or_env.is_a?(Array)
      args_or_env.join(" ")
    else
      args_or_env
    end

    env_export = +""
    env.each { |key, value| env_export << "#{key}=\"#{value}\" " }

    dirname.mkpath

    write <<~SH
      #!/bin/bash
      #{env_export}exec "#{target}" #{args} "$@"
    SH
    chmod 0555
  end

  # Writes a wrapper env script and moves all files to the dst.
  #
  # @api public
  sig { params(dst: Pathname, env: T::Hash[T.any(String, Symbol), T.any(String, Pathname)]).void }
  def env_script_all_files(dst, env)
    dst.mkpath
    Pathname.glob("#{self}/*") do |file|
      next if file.directory?

      new_file = dst.join(file.basename)
      raise Errno::EEXIST, new_file.to_s if new_file.exist?

      dst.install(file)
      file.write_env_script(new_file, env)
    end
  end

  # Writes an exec script that invokes a Java jar.
  #
  # @api public
  sig {
    params(
      target_jar:   T.any(String, Pathname),
      script_name:  T.any(String, Pathname),
      java_opts:    String,
      java_version: T.nilable(String),
    ).returns(Integer)
  }
  def write_jar_script(target_jar, script_name, java_opts = "", java_version: nil)
    mkpath
    (self/script_name).write <<~EOS
      #!/bin/bash
      export JAVA_HOME="#{Language::Java.overridable_java_home_env(java_version)[:JAVA_HOME]}"
      exec "${JAVA_HOME}/bin/java" #{java_opts} -jar "#{target_jar}" "$@"
    EOS
  end

  sig { params(from: T.any(String, Pathname)).void }
  def install_metafiles(from = Pathname.pwd)
    require "metafiles"

    Pathname(from).children.each do |p|
      next if p.directory?
      next if File.empty?(p)
      next unless Metafiles.copy?(p.basename.to_s)

      # Some software symlinks these files (see help2man.rb)
      filename = Utils::Path.resolved_path(p)
      # Some software links metafiles together, so by the time we iterate to one of them
      # we may have already moved it. libxml2's COPYING and Copyright are affected by this.
      next unless filename.exist?

      filename.chmod 0644
      install(filename)
    end
  end

  sig { returns(T::Boolean) }
  def binary_executable?
    false
  end

  sig { returns(T::Boolean) }
  def mach_o_bundle?
    false
  end

  sig { returns(T::Boolean) }
  def dylib?
    false
  end

  sig { params(_wanted_arch: Symbol).returns(T::Boolean) }
  def arch_compatible?(_wanted_arch)
    true
  end

  sig { returns(T::Array[String]) }
  def rpaths
    []
  end

  private

  sig {
    params(src: T.any(String, Pathname), new_basename: T.any(String, Pathname),
           _block: T.nilable(T.proc.params(src: Pathname, dst: Pathname).returns(T.nilable(Pathname)))).void
  }
  def install_p(src, new_basename, &_block)
    src = Pathname(src)
    raise Errno::ENOENT, src.to_s if !src.symlink? && !src.exist?

    dst = join(new_basename)
    dst = yield(src, dst) if block_given?
    return unless dst

    mkpath

    # Use `FileUtils.mv` over `File.rename` to handle filesystem boundaries. If `src`
    # is a symlink and its target is moved first, `FileUtils.mv` will fail
    # (https://bugs.ruby-lang.org/issues/7707).
    #
    # In that case, use the system `mv` command.
    if src.symlink?
      raise unless Kernel.system "mv", src.to_s, dst.to_s
    else
      FileUtils.mv src, dst
    end
  end

  sig { params(src: T.any(String, Pathname), new_basename: T.any(String, Pathname)).void }
  def install_symlink_p(src, new_basename)
    mkpath
    dstdir = realpath
    src = Pathname(src).expand_path(dstdir)
    src = src.dirname.realpath/src.basename if src.dirname.exist?
    FileUtils.ln_sf(src.relative_path_from(dstdir), dstdir/new_basename)
  end
end
# rubocop:enable Style/OneClassPerFile
#
require "extend/os/pathname"
