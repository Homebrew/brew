# typed: strict
# frozen_string_literal: true

require "system_command"
require "extend/pathname/disk_usage_extension"
require "extend/pathname/observer_pathname_extension"
require "extend/pathname/write_mkpath_extension"
require "utils/output"

# Stubs needed to keep Sorbet happy.
module MachOShim; end
module ELFShim; end

# @api private
module BinaryPathname
  sig { params(path: T.any(Pathname, String, MachOShim, ELFShim)).returns(T.any(MachOShim, ELFShim)) }
  def self.wrap(path) = raise NotImplementedError
end

# Homebrew extends Ruby's `Pathname` to make our code more readable.
# @see https://ruby-doc.org/stdlib-2.6.3/libdoc/pathname/rdoc/Pathname.html Ruby's Pathname API
class Pathname
  include SystemCommand::Mixin
  include DiskUsageExtension
  include Utils::Output::Mixin

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
      T::Array[T.any(String, Pathname)], T::Hash[T.any(String, Pathname), String]
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
      sources: T.any(String, Pathname, T::Array[T.any(String, Pathname)], T::Hash[T.any(String, Pathname), String]),
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

    T.unsafe(self).open("a", **open_args) { |f| f.puts(content) }
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
           _block: T.nilable(T.proc.params(src: Pathname, dst: Pathname).returns(Pathname))).void
  }
  def cp_path_sub(pattern, replacement, &_block)
    raise "#{self} does not exist" unless exist?

    pattern = pattern.to_s if pattern.is_a?(Pathname)
    replacement = replacement.to_s if replacement.is_a?(Pathname)
    dst = sub(pattern, replacement)

    raise "#{self} is the same file as #{dst}" if self == dst

    if directory?
      dst.mkpath
    else
      dst.dirname.mkpath
      dst = yield(self, dst) if block_given?
      FileUtils.cp(self, dst)
    end
  end

  # Extended to support common double extensions.
  #
  # @api public
  sig { returns(String) }
  def extname
    basename = File.basename(self)

    bottle_ext, = HOMEBREW_BOTTLES_EXTNAME_REGEX.match(basename).to_a
    return bottle_ext if bottle_ext

    archive_ext = basename[/(\.(tar|cpio|pax)\.(gz|bz2|lz|xz|zst|Z))\Z/, 1]
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

  # I don't trust the children.length == 0 check particularly, not to mention
  # it is slow to enumerate the whole directory just to see if it is empty,
  # instead rely on good ol' libc and the filesystem
  sig { returns(T::Boolean) }
  def rmdir_if_possible
    rmdir
    true
  rescue Errno::ENOTEMPTY
    if (ds_store = join(".DS_Store")).exist? && children.length == 1
      ds_store.unlink
      retry
    else
      false
    end
  rescue Errno::EACCES, Errno::ENOENT, Errno::EBUSY, Errno::EPERM
    false
  end

  sig { returns(Version) }
  def version
    require "version"
    Version.parse(basename)
  end

  sig { returns(T::Boolean) }
  def text_executable?
    /\A#!\s*\S+/.match?(open("r") { |f| f.read(1024) })
  end

  sig { returns(String) }
  def sha256
    require "digest/sha2"
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
    symlink? ? dirname.join(readlink) : self
  end

  sig { returns(T::Boolean) }
  def resolved_path_exists?
    link = readlink
  rescue ArgumentError
    # The link target contains NUL bytes
    false
  else
    dirname.join(link).exist?
  end

  sig { params(src: Pathname).void }
  def make_relative_symlink(src)
    dirname.mkpath
    File.symlink(src.relative_path_from(dirname), self)
  end

  sig { params(_block: T.proc.void).void }
  def ensure_writable(&_block)
    saved_perms = nil
    unless writable?
      saved_perms = stat.mode
      FileUtils.chmod "u+rw", to_path
    end
    yield
  ensure
    chmod saved_perms if saved_perms
  end

  sig { void }
  def install_info
    quiet_system(which_install_info, "--quiet", to_s, "#{dirname}/dir")
  end

  sig { void }
  def uninstall_info
    quiet_system(which_install_info, "--delete", "--quiet", to_s, "#{dirname}/dir")
  end

  # Writes an exec script in this folder for each target pathname.
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
  sig {
    params(target:      T.any(Pathname, String),
           args_or_env: T.any(String, T::Array[String], T::Hash[String, String], T::Hash[Symbol, String]),
           env:         T.any(T::Hash[String, String], T::Hash[Symbol, String])).void
  }
  def write_env_script(target, args_or_env, env = T.unsafe(nil))
    args = if env.nil?
      env = args_or_env if args_or_env.is_a?(Hash)

      nil
    elsif args_or_env.is_a?(Array)
      args_or_env.join(" ")
    else
      T.cast(args_or_env, T.nilable(String))
    end

    env_export = +""
    env.each { |key, value| env_export << "#{key}=\"#{value}\" " }

    dirname.mkpath

    write <<~SH
      #!/bin/bash
      #{env_export}exec "#{target}" #{args} "$@"
    SH
  end

  # Writes a wrapper env script and moves all files to the dst.
  sig { params(dst: Pathname, env: T::Hash[String, String]).void }
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
      filename = p.resolved_path
      # Some software links metafiles together, so by the time we iterate to one of them
      # we may have already moved it. libxml2's COPYING and Copyright are affected by this.
      next unless filename.exist?

      filename.chmod 0644
      install(filename)
    end
  end

  sig { returns(T::Boolean) }
  def ds_store?
    basename.to_s == ".DS_Store"
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

  sig { returns(String) }
  def magic_number
    @magic_number ||= T.let(nil, T.nilable(String))
    @magic_number ||= if directory?
      ""
    else
      # Length of the longest regex (currently Tar).
      max_magic_number_length = 262
      binread(max_magic_number_length) || ""
    end
  end

  sig { returns(String) }
  def file_type
    @file_type ||= T.let(nil, T.nilable(String))
    @file_type ||= system_command("file", args: ["-b", self], print_stderr: false)
                   .stdout.chomp
  end

  sig { returns(T::Array[String]) }
  def zipinfo
    @zipinfo ||= T.let(
      system_command("zipinfo", args: ["-1", self], print_stderr: false)
      .stdout
      .encode(Encoding::UTF_8, invalid: :replace)
      .split("\n"),
      T.nilable(T::Array[String]),
    )
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

  sig { returns(T.nilable(String)) }
  def which_install_info
    @which_install_info ||= T.let(nil, T.nilable(String))
    @which_install_info ||=
      if File.executable?("/usr/bin/install-info")
        "/usr/bin/install-info"
      elsif (texinfo_formula = Formulary.factory_stub("texinfo")).any_version_installed?
        (texinfo_formula.opt_bin/"install-info").to_s
      end
  end
end
require "extend/os/pathname"
