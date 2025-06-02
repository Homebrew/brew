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
#   Tempfile.open('foo') do |file|
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
  # Creates a temporary file with permissions 0600 (= only readable and
  # writable by the owner) and opens it with mode "w+".
  #
  # It is recommended to use Tempfile.create { ... } instead when possible,
  # because that method avoids the cost of delegation and does not rely on a
  # finalizer to close and unlink the file, which is unreliable.
  #
  # The +basename+ parameter is used to determine the name of the
  # temporary file. You can either pass a String or an Array with
  # 2 String elements. In the former form, the temporary file's base
  # name will begin with the given string. In the latter form,
  # the temporary file's base name will begin with the array's first
  # element, and end with the second element. For example:
  #
  #   file = Tempfile.new('hello')
  #   file.path  # => something like: "/tmp/hello2843-8392-92849382--0"
  #
  #   # Use the Array form to enforce an extension in the filename:
  #   file = Tempfile.new(['hello', '.jpg'])
  #   file.path  # => something like: "/tmp/hello2843-8392-92849382--0.jpg"
  #
  # The temporary file will be placed in the directory as specified
  # by the +tmpdir+ parameter. By default, this is +Dir.tmpdir+.
  #
  #   file = Tempfile.new('hello', '/home/aisaka')
  #   file.path  # => something like: "/home/aisaka/hello2843-8392-92849382--0"
  #
  # You can also pass an options hash. Under the hood, Tempfile creates
  # the temporary file using +File.open+. These options will be passed to
  # +File.open+. This is mostly useful for specifying encoding
  # options, e.g.:
  #
  #   Tempfile.new('hello', '/home/aisaka', encoding: 'ascii-8bit')
  #
  #   # You can also omit the 'tmpdir' parameter:
  #   Tempfile.new('hello', encoding: 'ascii-8bit')
  #
  # Note: +mode+ keyword argument, as accepted by Tempfile, can only be
  # numeric, combination of the modes defined in File::Constants.
  #
  # === Exceptions
  #
  # If Tempfile.new cannot find a unique filename within a limited
  # number of tries, then it will raise an exception.
  def initialize(basename="", tmpdir=nil, mode: 0, **options)
    warn "Tempfile.new doesn't call the given block.", uplevel: 1 if block_given?

    @unlinked = false
    @mode = mode|File::RDWR|File::CREAT|File::EXCL
    ::Dir::Tmpname.create(basename, tmpdir, **options) do |tmpname, n, opts|
      opts[:perm] = 0600
      @tmpfile = File.open(tmpname, @mode, **opts)
      @opts = opts.freeze
    end
    ObjectSpace.define_finalizer(self, Remover.new(@tmpfile))

    super(@tmpfile)
  end

  # Opens or reopens the file with mode "r+".
  def open
    _close
    mode = @mode & ~(File::CREAT|File::EXCL)
    @tmpfile = File.open(@tmpfile.path, mode, **@opts)
    __setobj__(@tmpfile)
  end

  def _close    # :nodoc:
    @tmpfile.close
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
      File.unlink(@tmpfile.path)
    rescue Errno::ENOENT
    rescue Errno::EACCES
      # may not be able to unlink on Windows; just ignore
      return
    end
    ObjectSpace.undefine_finalizer(self)
    @unlinked = true
  end
  alias delete unlink

  # Returns the full path name of the temporary file.
  # This will be nil if #unlink has been called.
  def path
    @unlinked ? nil : @tmpfile.path
  end

  # Returns the size of the temporary file.  As a side effect, the IO
  # buffer is flushed before determining the size.
  def size
    if !@tmpfile.closed?
      @tmpfile.size # File#size calls rb_io_flush_raw()
    else
      File.size(@tmpfile.path)
    end
  end
  alias length size

  # :stopdoc:
  def inspect
    if @tmpfile.closed?
      "#<#{self.class}:#{path} (closed)>"
    else
      "#<#{self.class}:#{path}>"
    end
  end

  class Remover # :nodoc:
    def initialize(tmpfile)
      @pid = Process.pid
      @tmpfile = tmpfile
    end

    def call(*args)
      return if @pid != Process.pid

      $stderr.puts "removing #{@tmpfile.path}..." if $DEBUG

      @tmpfile.close
      begin
        File.unlink(@tmpfile.path)
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

# Creates a temporary file as a usual File object (not a Tempfile).
# It does not use finalizer and delegation, which makes it more efficient and reliable.
#
# If no block is given, this is similar to Tempfile.new except
# creating File instead of Tempfile. In that case, the created file is
# not removed automatically. You should use File.unlink to remove it.
#
# If a block is given, then a File object will be constructed,
# and the block is invoked with the object as the argument.
# The File object will be automatically closed and
# the temporary file is removed after the block terminates,
# releasing all resources that the block created.
# The call returns the value of the block.
#
# In any case, all arguments (+basename+, +tmpdir+, +mode+, and
# <code>**options</code>) will be treated the same as for Tempfile.new.
#
#   Tempfile.create('foo', '/home/temp') do |f|
#      # ... do something with f ...
#   end
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
