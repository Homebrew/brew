# frozen_string_literal: true
#
# tempfile - manipulates temporary files
#
# $Id$
#

require 'delegate'
require 'tmpdir'

# A utility class for managing temporary files. When you create a Tempfile
# object, it will create a temporary file with a unique filename. A Tempfile
# objects behaves just like a File object, and you can perform all the usual
# file operations on it: reading data, writing data, changing its permissions,
# etc. So although this class does not explicitly document all instance methods
# supported by File, you can in fact call any File instance method on a
# Tempfile object.
#
# == Synopsis
#
#   require 'tempfile'
#
#   file = Tempfile.new('foo')
#   file.path      # => A unique filename in the OS's temp directory,
#                  #    e.g.: "/tmp/foo.24722.0"
#                  #    This filename contains 'foo' in its basename.
#   file.write("hello world")
#   file.rewind
#   file.read      # => "hello world"
#   file.close
#   file.unlink    # deletes the temp file
#
# == Good practices
#
# === Explicit close
#
# When a Tempfile object is garbage collected, or when the Ruby interpreter
# exits, its associated temporary file is automatically deleted. This means
# that it's unnecessary to explicitly delete a Tempfile after use, though
# it's a good practice to do so: not explicitly deleting unused Tempfiles can
# potentially leave behind a large number of temp files on the filesystem
# until they're garbage collected. The existence of these temp files can make
# it harder to determine a new Tempfile filename.
#
# Therefore, one should always call #unlink or close in an ensure block, like
# this:
#
#   file = Tempfile.new('foo')
#   begin
#      # ...do something with file...
#   ensure
#      file.close
#      file.unlink   # deletes the temp file
#   end
#
# Tempfile.create { ... } exists for this purpose and is more convenient to use.
# Note that Tempfile.create returns a File instance instead of a Tempfile, which
# also avoids the overhead and complications of delegation.
#
#   Tempfile.create('foo') do |file|
#      # ...do something with file...
#   end
#
# === Unlink after creation
#
# On POSIX systems, it's possible to unlink a file right after creating it,
# and before closing it. This removes the filesystem entry without closing
# the file handle, so it ensures that only the processes that already had
# the file handle open can access the file's contents. It's strongly
# recommended that you do this if you do not want any other processes to
# be able to read from or write to the Tempfile, and you do not need to
# know the Tempfile's filename either.
#
# For example, a practical use case for unlink-after-creation would be this:
# you need a large byte buffer that's too large to comfortably fit in RAM,
# e.g. when you're writing a web server and you want to buffer the client's
# file upload data.
#
# Please refer to #unlink for more information and a code example.
#
# == Minor notes
#
# Tempfile's filename picking method is both thread-safe and inter-process-safe:
# it guarantees that no other threads or processes will pick the same filename.
#
# Tempfile itself however may not be entirely thread-safe. If you access the
# same Tempfile object from multiple threads then you should protect it with a
# mutex.
class Tempfile < DelegateClass(File)

  VERSION = "0.2.1"

  # Creates a file in the underlying file system;
  # returns a new \Tempfile object based on that file.
  #
  # If possible, consider instead using Tempfile.create, which:
  #
  # - Avoids the performance cost of delegation,
  #   incurred when Tempfile.new calls its superclass <tt>DelegateClass(File)</tt>.
  # - Does not rely on a finalizer to close and unlink the file,
  #   which can be unreliable.
  #
  # Creates and returns file whose:
  #
  # - Class is \Tempfile (not \File, as in Tempfile.create).
  # - Directory is the system temporary directory (system-dependent).
  # - Generated filename is unique in that directory.
  # - Permissions are <tt>0600</tt>;
  #   see {File Permissions}[rdoc-ref:File@File+Permissions].
  # - Mode is <tt>'w+'</tt> (read/write mode, positioned at the end).
  #
  # The underlying file is removed when the \Tempfile object dies
  # and is reclaimed by the garbage collector.
  #
  # Example:
  #
  #   f = Tempfile.new # => #<Tempfile:/tmp/20220505-17839-1s0kt30>
  #   f.class               # => Tempfile
  #   f.path                # => "/tmp/20220505-17839-1s0kt30"
  #   f.stat.mode.to_s(8)   # => "100600"
  #   File.exist?(f.path)   # => true
  #   File.unlink(f.path)   #
  #   File.exist?(f.path)   # => false
  #
  # Argument +basename+, if given, may be one of:
  #
  # - A string: the generated filename begins with +basename+:
  #
  #     Tempfile.new('foo') # => #<Tempfile:/tmp/foo20220505-17839-1whk2f>
  #
  # - An array of two strings <tt>[prefix, suffix]</tt>:
  #   the generated filename begins with +prefix+ and ends with +suffix+:
  #
  #     Tempfile.new(%w/foo .jpg/) # => #<Tempfile:/tmp/foo20220505-17839-58xtfi.jpg>
  #
  # With arguments +basename+ and +tmpdir+, the file is created in directory +tmpdir+:
  #
  #   Tempfile.new('foo', '.') # => #<Tempfile:./foo20220505-17839-xfstr8>
  #
  # Keyword arguments +mode+ and +options+ are passed directly to method
  # {File.open}[rdoc-ref:File.open]:
  #
  # - The value given with +mode+ must be an integer,
  #   and may be expressed as the logical OR of constants defined in
  #   {File::Constants}[rdoc-ref:File::Constants].
  # - For +options+, see {Open Options}[rdoc-ref:IO@Open+Options].
  #
  # Related: Tempfile.create.
  #
  def initialize(basename="", tmpdir=nil, mode: 0, **options)
    warn "Tempfile.new doesn't call the given block.", uplevel: 1 if block_given?

    @unlinked = false
    @mode = mode|File::RDWR|File::CREAT|File::EXCL
    @finalizer_obj = Object.new
    tmpfile = nil
    ::Dir::Tmpname.create(basename, tmpdir, **options) do |tmpname, n, opts|
      opts[:perm] = 0600
      tmpfile = File.open(tmpname, @mode, **opts)
      @opts = opts.freeze
    end
    ObjectSpace.define_finalizer(@finalizer_obj, Remover.new(tmpfile.path))
    ObjectSpace.define_finalizer(self, Closer.new(tmpfile))

    super(tmpfile)
  end

  def initialize_dup(other)
    initialize_copy_iv(other)
    super(other)
    ObjectSpace.define_finalizer(self, Closer.new(__getobj__))
  end

  def initialize_clone(other)
    initialize_copy_iv(other)
    super(other)
    ObjectSpace.define_finalizer(self, Closer.new(__getobj__))
  end

  private def initialize_copy_iv(other)
    @unlinked = other.unlinked
    @mode = other.mode
    @opts = other.opts
    @finalizer_obj = other.finalizer_obj
  end

  # Opens or reopens the file with mode "r+".
  def open
    _close
    ObjectSpace.undefine_finalizer(self)
    mode = @mode & ~(File::CREAT|File::EXCL)
    __setobj__(File.open(__getobj__.path, mode, **@opts))
    ObjectSpace.define_finalizer(self, Closer.new(__getobj__))
    __getobj__
  end

  def _close    # :nodoc:
    __getobj__.close
  end
  protected :_close

  # Closes the file. If +unlink_now+ is true, then the file will be unlinked
  # (deleted) after closing. Of course, you can choose to later call #unlink
  # if you do not unlink it now.
  #
  # If you don't explicitly unlink the temporary file, the removal
  # will be delayed until the object is finalized.
  def close(unlink_now=false)
    _close
    unlink if unlink_now
  end

  # Closes and unlinks (deletes) the file. Has the same effect as called
  # <tt>close(true)</tt>.
  def close!
    close(true)
  end

  # Unlinks (deletes) the file from the filesystem. One should always unlink
  # the file after using it, as is explained in the "Explicit close" good
  # practice section in the Tempfile overview:
  #
  #   file = Tempfile.new('foo')
  #   begin
  #      # ...do something with file...
  #   ensure
  #      file.close
  #      file.unlink   # deletes the temp file
  #   end
  #
  # === Unlink-before-close
  #
  # On POSIX systems it's possible to unlink a file before closing it. This
  # practice is explained in detail in the Tempfile overview (section
  # "Unlink after creation"); please refer there for more information.
  #
  # However, unlink-before-close may not be supported on non-POSIX operating
  # systems. Microsoft Windows is the most notable case: unlinking a non-closed
  # file will result in an error, which this method will silently ignore. If
  # you want to practice unlink-before-close whenever possible, then you should
  # write code like this:
  #
  #   file = Tempfile.new('foo')
  #   file.unlink   # On Windows this silently fails.
  #   begin
  #      # ... do something with file ...
  #   ensure
  #      file.close!   # Closes the file handle. If the file wasn't unlinked
  #                    # because #unlink failed, then this method will attempt
  #                    # to do so again.
  #   end
  def unlink
    return if @unlinked
    begin
      File.unlink(__getobj__.path)
    rescue Errno::ENOENT
    rescue Errno::EACCES
      # may not be able to unlink on Windows; just ignore
      return
    end
    ObjectSpace.undefine_finalizer(@finalizer_obj)
    @unlinked = true
  end
  alias delete unlink

  # Returns the full path name of the temporary file.
  # This will be nil if #unlink has been called.
  def path
    @unlinked ? nil : __getobj__.path
  end

  # Returns the size of the temporary file.  As a side effect, the IO
  # buffer is flushed before determining the size.
  def size
    if !__getobj__.closed?
      __getobj__.size # File#size calls rb_io_flush_raw()
    else
      File.size(__getobj__.path)
    end
  end
  alias length size

  # :stopdoc:
  def inspect
    if __getobj__.closed?
      "#<#{self.class}:#{path} (closed)>"
    else
      "#<#{self.class}:#{path}>"
    end
  end
  alias to_s inspect

  protected

  attr_reader :unlinked, :mode, :opts, :finalizer_obj

  class Closer # :nodoc:
    def initialize(tmpfile)
      @tmpfile = tmpfile
    end

    def call(*args)
      @tmpfile.close
    end
  end

  class Remover # :nodoc:
    def initialize(path)
      @pid = Process.pid
      @path = path
    end

    def call(*args)
      return if @pid != Process.pid

      $stderr.puts "removing #{@path}..." if $DEBUG

      begin
        File.unlink(@path)
      rescue Errno::ENOENT
      end

      $stderr.puts "done" if $DEBUG
    end
  end

  class << self
    # :startdoc:

    # Creates a new Tempfile.
    #
    # This method is not recommended and exists mostly for backward compatibility.
    # Please use Tempfile.create instead, which avoids the cost of delegation,
    # does not rely on a finalizer, and also unlinks the file when given a block.
    #
    # Tempfile.open is still appropriate if you need the Tempfile to be unlinked
    # by a finalizer and you cannot explicitly know where in the program the
    # Tempfile can be unlinked safely.
    #
    # If no block is given, this is a synonym for Tempfile.new.
    #
    # If a block is given, then a Tempfile object will be constructed,
    # and the block is run with the Tempfile object as argument. The Tempfile
    # object will be automatically closed after the block terminates.
    # However, the file will *not* be unlinked and needs to be manually unlinked
    # with Tempfile#close! or Tempfile#unlink. The finalizer will try to unlink
    # but should not be relied upon as it can keep the file on the disk much
    # longer than intended. For instance, on CRuby, finalizers can be delayed
    # due to conservative stack scanning and references left in unused memory.
    #
    # The call returns the value of the block.
    #
    # In any case, all arguments (<code>*args</code>) will be passed to Tempfile.new.
    #
    #   Tempfile.open('foo', '/home/temp') do |f|
    #      # ... do something with f ...
    #   end
    #
    #   # Equivalent:
    #   f = Tempfile.open('foo', '/home/temp')
    #   begin
    #      # ... do something with f ...
    #   ensure
    #      f.close
    #   end
    def open(*args, **kw)
      tempfile = new(*args, **kw)

      if block_given?
        begin
          yield(tempfile)
        ensure
          tempfile.close
        end
      else
        tempfile
      end
    end
  end
end

# Creates a file in the underlying file system;
# returns a new \File object based on that file.
#
# With no block given and no arguments, creates and returns file whose:
#
# - Class is {File}[rdoc-ref:File] (not \Tempfile).
# - Directory is the system temporary directory (system-dependent).
# - Generated filename is unique in that directory.
# - Permissions are <tt>0600</tt>;
#   see {File Permissions}[rdoc-ref:File@File+Permissions].
# - Mode is <tt>'w+'</tt> (read/write mode, positioned at the end).
#
# With no block, the file is not removed automatically,
# and so should be explicitly removed.
#
# Example:
#
#   f = Tempfile.create     # => #<File:/tmp/20220505-9795-17ky6f6>
#   f.class                 # => File
#   f.path                  # => "/tmp/20220505-9795-17ky6f6"
#   f.stat.mode.to_s(8)     # => "100600"
#   File.exist?(f.path)     # => true
#   File.unlink(f.path)
#   File.exist?(f.path)     # => false
#
# Argument +basename+, if given, may be one of:
#
# - A string: the generated filename begins with +basename+:
#
#     Tempfile.create('foo') # => #<File:/tmp/foo20220505-9795-1gok8l9>
#
# - An array of two strings <tt>[prefix, suffix]</tt>:
#   the generated filename begins with +prefix+ and ends with +suffix+:
#
#     Tempfile.create(%w/foo .jpg/) # => #<File:/tmp/foo20220505-17839-tnjchh.jpg>
#
# With arguments +basename+ and +tmpdir+, the file is created in directory +tmpdir+:
#
#   Tempfile.create('foo', '.') # => #<File:./foo20220505-9795-1emu6g8>
#
# Keyword arguments +mode+ and +options+ are passed directly to method
# {File.open}[rdoc-ref:File.open]:
#
# - The value given with +mode+ must be an integer,
#   and may be expressed as the logical OR of constants defined in
#   {File::Constants}[rdoc-ref:File::Constants].
# - For +options+, see {Open Options}[rdoc-ref:IO@Open+Options].
#
# With a block given, creates the file as above, passes it to the block,
# and returns the block's value;
# before the return, the file object is closed and the underlying file is removed:
#
#   Tempfile.create {|file| file.path } # => "/tmp/20220505-9795-rkists"
#
# Related: Tempfile.new.
#
def Tempfile.create(basename="", tmpdir=nil, mode: 0, **options)
  tmpfile = nil
  Dir::Tmpname.create(basename, tmpdir, **options) do |tmpname, n, opts|
    mode |= File::RDWR|File::CREAT|File::EXCL
    opts[:perm] = 0600
    tmpfile = File.open(tmpname, mode, **opts)
  end
  if block_given?
    begin
      yield tmpfile
    ensure
      unless tmpfile.closed?
        if File.identical?(tmpfile, tmpfile.path)
          unlinked = File.unlink tmpfile.path rescue nil
        end
        tmpfile.close
      end
      unless unlinked
        begin
          File.unlink tmpfile.path
        rescue Errno::ENOENT
        end
      end
    end
  else
    tmpfile
  end
end
