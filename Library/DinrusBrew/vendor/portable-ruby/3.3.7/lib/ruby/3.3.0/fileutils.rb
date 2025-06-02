# frozen_string_literal: true

begin
  require 'rbconfig'
rescue LoadError
  # for make rjit-headers
end

# Namespace for file utility methods for copying, moving, removing, etc.
#
# == What's Here
#
# First, what’s elsewhere. \Module \FileUtils:
#
# - Inherits from {class Object}[rdoc-ref:Object].
# - Supplements {class File}[rdoc-ref:File]
#   (but is not included or extended there).
#
# Here, module \FileUtils provides methods that are useful for:
#
# - {Creating}[rdoc-ref:FileUtils@Creating].
# - {Deleting}[rdoc-ref:FileUtils@Deleting].
# - {Querying}[rdoc-ref:FileUtils@Querying].
# - {Setting}[rdoc-ref:FileUtils@Setting].
# - {Comparing}[rdoc-ref:FileUtils@Comparing].
# - {Copying}[rdoc-ref:FileUtils@Copying].
# - {Moving}[rdoc-ref:FileUtils@Moving].
# - {Options}[rdoc-ref:FileUtils@Options].
#
# === Creating
#
# - ::mkdir: Creates directories.
# - ::mkdir_p, ::makedirs, ::mkpath: Creates directories,
#   also creating ancestor directories as needed.
# - ::link_entry: Creates a hard link.
# - ::ln, ::link: Creates hard links.
# - ::ln_s, ::symlink: Creates symbolic links.
# - ::ln_sf: Creates symbolic links, overwriting if necessary.
# - ::ln_sr: Creates symbolic links relative to targets
#
# === Deleting
#
# - ::remove_dir: Removes a directory and its descendants.
# - ::remove_entry: Removes an entry, including its descendants if it is a directory.
# - ::remove_entry_secure: Like ::remove_entry, but removes securely.
# - ::remove_file: Removes a file entry.
# - ::rm, ::remove: Removes entries.
# - ::rm_f, ::safe_unlink: Like ::rm, but removes forcibly.
# - ::rm_r: Removes entries and their descendants.
# - ::rm_rf, ::rmtree: Like ::rm_r, but removes forcibly.
# - ::rmdir: Removes directories.
#
# === Querying
#
# - ::pwd, ::getwd: Returns the path to the working directory.
# - ::uptodate?: Returns whether a given entry is newer than given other entries.
#
# === Setting
#
# - ::cd, ::chdir: Sets the working directory.
# - ::chmod: Sets permissions for an entry.
# - ::chmod_R: Sets permissions for an entry and its descendants.
# - ::chown: Sets the owner and group for entries.
# - ::chown_R: Sets the owner and group for entries and their descendants.
# - ::touch: Sets modification and access times for entries,
#   creating if necessary.
#
# === Comparing
#
# - ::compare_file, ::cmp, ::identical?: Returns whether two entries are identical.
# - ::compare_stream: Returns whether two streams are identical.
#
# === Copying
#
# - ::copy_entry: Recursively copies an entry.
# - ::copy_file: Copies an entry.
# - ::copy_stream: Copies a stream.
# - ::cp, ::copy: Copies files.
# - ::cp_lr: Recursively creates hard links.
# - ::cp_r: Recursively copies files, retaining mode, owner, and group.
# - ::install: Recursively copies files, optionally setting mode,
#   owner, and group.
#
# === Moving
#
# - ::mv, ::move: Moves entries.
#
# === Options
#
# - ::collect_method: Returns the names of methods that accept a given option.
# - ::commands: Returns the names of methods that accept options.
# - ::have_option?: Returns whether a given method accepts a given option.
# - ::options: Returns all option names.
# - ::options_of: Returns the names of the options for a given method.
#
# == Path Arguments
#
# Some methods in \FileUtils accept _path_ arguments,
# which are interpreted as paths to filesystem entries:
#
# - If the argument is a string, that value is the path.
# - If the argument has method +:to_path+, it is converted via that method.
# - If the argument has method +:to_str+, it is converted via that method.
#
# == About the Examples
#
# Some examples here involve trees of file entries.
# For these, we sometimes display trees using the
# {tree command-line utility}[https://en.wikipedia.org/wiki/Tree_(command)],
# which is a recursive directory-listing utility that produces
# a depth-indented listing of files and directories.
#
# We use a helper method to launch the command and control the format:
#
#   def tree(dirpath = '.')
#     command = "tree --noreport --charset=ascii #{dirpath}"
#     system(command)
#   end
#
# To illustrate:
#
#   tree('src0')
#   # => src0
#   #    |-- sub0
#   #    |   |-- src0.txt
#   #    |   `-- src1.txt
#   #    `-- sub1
#   #        |-- src2.txt
#   #        `-- src3.txt
#
# == Avoiding the TOCTTOU Vulnerability
#
# For certain methods that recursively remove entries,
# there is a potential vulnerability called the
# {Time-of-check to time-of-use}[https://en.wikipedia.org/wiki/Time-of-check_to_time-of-use],
# or TOCTTOU, vulnerability that can exist when:
#
# - An ancestor directory of the entry at the target path is world writable;
#   such directories include <tt>/tmp</tt>.
# - The directory tree at the target path includes:
#
#   - A world-writable descendant directory.
#   - A symbolic link.
#
# To avoid that vulnerability, you can use this method to remove entries:
#
# - FileUtils.remove_entry_secure: removes recursively
#   if the target path points to a directory.
#
# Also available are these methods,
# each of which calls \FileUtils.remove_entry_secure:
#
# - FileUtils.rm_r with keyword argument <tt>secure: true</tt>.
# - FileUtils.rm_rf with keyword argument <tt>secure: true</tt>.
#
# Finally, this method for moving entries calls \FileUtils.remove_entry_secure
# if the source and destination are on different file systems
# (which means that the "move" is really a copy and remove):
#
# - FileUtils.mv with keyword argument <tt>secure: true</tt>.
#
# \Method \FileUtils.remove_entry_secure removes securely
# by applying a special pre-process:
#
# - If the target path points to a directory, this method uses methods
#   {File#chown}[rdoc-ref:File#chown]
#   and {File#chmod}[rdoc-ref:File#chmod]
#   in removing directories.
# - The owner of the target directory should be either the current process
#   or the super user (root).
#
# WARNING: You must ensure that *ALL* parent directories cannot be
# moved by other untrusted users.  For example, parent directories
# should not be owned by untrusted users, and should not be world
# writable except when the sticky bit is set.
#
# For details of this security vulnerability, see Perl cases:
#
# - {CVE-2005-0448}[https://cve.mitre.org/cgi-bin/cvename.cgi?name=CAN-2005-0448].
# - {CVE-2004-0452}[https://cve.mitre.org/cgi-bin/cvename.cgi?name=CAN-2004-0452].
#
module FileUtils
  VERSION = "1.7.2"

  def self.private_module_function(name)   #:nodoc:
    module_function name
    private_class_method name
  end

  #
  # Returns a string containing the path to the current directory:
  #
  #   FileUtils.pwd # => "/rdoc/fileutils"
  #
  # Related: FileUtils.cd.
  #
  def pwd
    Dir.pwd
  end
  module_function :pwd

  alias getwd pwd
  module_function :getwd

  # Changes the working directory to the given +dir+, which
  # should be {interpretable as a path}[rdoc-ref:FileUtils@Path+Arguments]:
  #
  # With no block given,
  # changes the current directory to the directory at +dir+; returns zero:
  #
  #   FileUtils.pwd # => "/rdoc/fileutils"
  #   FileUtils.cd('..')
  #   FileUtils.pwd # => "/rdoc"
  #   FileUtils.cd('fileutils')
  #
  # With a block given, changes the current directory to the directory
  # at +dir+, calls the block with argument +dir+,
  # and restores the original current directory; returns the block's value:
  #
  #   FileUtils.pwd                                     # => "/rdoc/fileutils"
  #   FileUtils.cd('..') { |arg| [arg, FileUtils.pwd] } # => ["..", "/rdoc"]
  #   FileUtils.pwd                                     # => "/rdoc/fileutils"
  #
  # Keyword arguments:
  #
  # - <tt>verbose: true</tt> - prints an equivalent command:
  #
  #     FileUtils.cd('..')
  #     FileUtils.cd('fileutils')
  #
  #   Output:
  #
  #     cd ..
  #     cd fileutils
  #
  # Related: FileUtils.pwd.
  #
  def cd(dir, verbose: nil, &block) # :yield: dir
    fu_output_message "cd #{dir}" if verbose
    result = Dir.chdir(dir, &block)
    fu_output_message 'cd -' if verbose and block
    result
  end
  module_function :cd

  alias chdir cd
  module_function :chdir

  #
  # Returns +true+ if the file at path +new+
  # is newer than all the files at paths in array +old_list+;
  # +false+ otherwise.
  #
  # Argument +new+ and the elements of +old_list+
  # should be {interpretable as paths}[rdoc-ref:FileUtils@Path+Arguments]:
  #
  #   FileUtils.uptodate?('Rakefile', ['Gemfile', 'README.md']) # => true
  #   FileUtils.uptodate?('Gemfile', ['Rakefile', 'README.md']) # => false
  #
  # A non-existent file is considered to be infinitely old.
  #
  # Related: FileUtils.touch.
  #
  def uptodate?(new, old_list)
    return false unless File.exist?(new)
    new_time = File.mtime(new)
    old_list.each do |old|
      if File.exist?(old)
        return false unless new_time > File.mtime(old)
      end
    end
    true
  end
  module_function :uptodate?

  def remove_trailing_slash(dir)   #:nodoc:
    dir == '/' ? dir : dir.chomp(?/)
  end
  private_module_function :remove_trailing_slash

  #
  # Creates directories at the paths in the given +list+
  # (a single path or an array of paths);
  # returns +list+ if it is an array, <tt>[list]</tt> otherwise.
  #
  # Argument +list+ or its elements
  # should be {interpretable as paths}[rdoc-ref:FileUtils@Path+Arguments].
  #
  # With no keyword arguments, creates a directory at each +path+ in +list+
  # by calling: <tt>Dir.mkdir(path, mode)</tt>;
  # see {Dir.mkdir}[rdoc-ref:Dir.mkdir]:
  #
  #   FileUtils.mkdir(%w[tmp0 tmp1]) # => ["tmp0", "tmp1"]
  #   FileUtils.mkdir('tmp4')        # => ["tmp4"]
  #
  # Keyword arguments:
  #
  # - <tt>mode: <i>mode</i></tt> - also calls <tt>File.chmod(mode, path)</tt>;
  #   see {File.chmod}[rdoc-ref:File.chmod].
  # - <tt>noop: true</tt> - does not create directories.
  # - <tt>verbose: true</tt> - prints an equivalent command:
  #
  #     FileUtils.mkdir(%w[tmp0 tmp1], verbose: true)
  #     FileUtils.mkdir(%w[tmp2 tmp3], mode: 0700, verbose: true)
  #
  #   Output:
  #
  #     mkdir tmp0 tmp1
  #     mkdir -m 700 tmp2 tmp3
  #
  # Raises an exception if any path points to an existing
  # file or directory, or if for any reason a directory cannot be created.
  #
  # Related: FileUtils.mkdir_p.
  #
  def mkdir(list, mode: nil, noop: nil, verbose: nil)
    list = fu_list(list)
    fu_output_message "mkdir #{mode ? ('-m %03o ' % mode) : ''}#{list.join ' '}" if verbose
    return if noop

    list.each do |dir|
      fu_mkdir dir, mode
    end
  end
  module_function :mkdir

  #
  # Creates directories at the paths in the given +list+
  # (a single path or an array of paths),
  # also creating ancestor directories as needed;
  # returns +list+ if it is an array, <tt>[list]</tt> otherwise.
  #
  # Argument +list+ or its elements
  # should be {interpretable as paths}[rdoc-ref:FileUtils@Path+Arguments].
  #
  # With no keyword arguments, creates a directory at each +path+ in +list+,
  # along with any needed ancestor directories,
  # by calling: <tt>Dir.mkdir(path, mode)</tt>;
  # see {Dir.mkdir}[rdoc-ref:Dir.mkdir]:
  #
  #   FileUtils.mkdir_p(%w[tmp0/tmp1 tmp2/tmp3]) # => ["tmp0/tmp1", "tmp2/tmp3"]
  #   FileUtils.mkdir_p('tmp4/tmp5')             # => ["tmp4/tmp5"]
  #
  # Keyword arguments:
  #
  # - <tt>mode: <i>mode</i></tt> - also calls <tt>File.chmod(mode, path)</tt>;
  #   see {File.chmod}[rdoc-ref:File.chmod].
  # - <tt>noop: true</tt> - does not create directories.
  # - <tt>verbose: true</tt> - prints an equivalent command:
  #
  #     FileUtils.mkdir_p(%w[tmp0 tmp1], verbose: true)
  #     FileUtils.mkdir_p(%w[tmp2 tmp3], mode: 0700, verbose: true)
  #
  #   Output:
  #
  #     mkdir -p tmp0 tmp1
  #     mkdir -p -m 700 tmp2 tmp3
  #
  # Raises an exception if for any reason a directory cannot be created.
  #
  # FileUtils.mkpath and FileUtils.makedirs are aliases for FileUtils.mkdir_p.
  #
  # Related: FileUtils.mkdir.
  #
  def mkdir_p(list, mode: nil, noop: nil, verbose: nil)
    list = fu_list(list)
    fu_output_message "mkdir -p #{mode ? ('-m %03o ' % mode) : ''}#{list.join ' '}" if verbose
    return *list if noop

    list.each do |item|
      path = remove_trailing_slash(item)

      stack = []
      until File.directory?(path) || File.dirname(path) == path
        stack.push path
        path = File.dirname(path)
      end
      stack.reverse_each do |dir|
        begin
          fu_mkdir dir, mode
        rescue SystemCallError
          raise unless File.directory?(dir)
        end
      end
    end

    return *list
  end
  module_function :mkdir_p

  alias mkpath    mkdir_p
  alias makedirs  mkdir_p
  module_function :mkpath
  module_function :makedirs

  def fu_mkdir(path, mode)   #:nodoc:
    path = remove_trailing_slash(path)
    if mode
      Dir.mkdir path, mode
      File.chmod mode, path
    else
      Dir.mkdir path
    end
  end
  private_module_function :fu_mkdir

  #
  # Removes directories at the paths in the given +list+
  # (a single path or an array of paths);
  # returns +list+, if it is an array, <tt>[list]</tt> otherwise.
  #
  # Argument +list+ or its elements
  # should be {interpretable as paths}[rdoc-ref:FileUtils@Path+Arguments].
  #
  # With no keyword arguments, removes the directory at each +path+ in +list+,
  # by calling: <tt>Dir.rmdir(path)</tt>;
  # see {Dir.rmdir}[rdoc-ref:Dir.rmdir]:
  #
  #   FileUtils.rmdir(%w[tmp0/tmp1 tmp2/tmp3]) # => ["tmp0/tmp1", "tmp2/tmp3"]
  #   FileUtils.rmdir('tmp4/tmp5')             # => ["tmp4/tmp5"]
  #
  # Keyword arguments:
  #
  # - <tt>parents: true</tt> - removes successive ancestor directories
  #   if empty.
  # - <tt>noop: true</tt> - does not remove directories.
  # - <tt>verbose: true</tt> - prints an equivalent command:
  #
  #     FileUtils.rmdir(%w[tmp0/tmp1 tmp2/tmp3], parents: true, verbose: true)
  #     FileUtils.rmdir('tmp4/tmp5', parents: true, verbose: true)
  #
  #   Output:
  #
  #     rmdir -p tmp0/tmp1 tmp2/tmp3
  #     rmdir -p tmp4/tmp5
  #
  # Raises an exception if a directory does not exist
  # or if for any reason a directory cannot be removed.
  #
  # Related: {methods for deleting}[rdoc-ref:FileUtils@Deleting].
  #
  def rmdir(list, parents: nil, noop: nil, verbose: nil)
    list = fu_list(list)
    fu_output_message "rmdir #{parents ? '-p ' : ''}#{list.join ' '}" if verbose
    return if noop
    list.each do |dir|
      Dir.rmdir(dir = remove_trailing_slash(dir))
      if parents
        begin
          until (parent = File.dirname(dir)) == '.' or parent == dir
            dir = parent
            Dir.rmdir(dir)
          end
        rescue Errno::ENOTEMPTY, Errno::EEXIST, Errno::ENOENT
        end
      end
    end
  end
  module_function :rmdir

  # Creates {hard links}[https://en.wikipedia.org/wiki/Hard_link].
  #
  # Arguments +src+ (a single path or an array of paths)
  # and +dest+ (a single path)
  # should be {interpretable as paths}[rdoc-ref:FileUtils@Path+Arguments].
  #
  # When +src+ is the path to an existing file
  # and +dest+ is the path to a non-existent file,
  # creates a hard link at +dest+ pointing to +src+; returns zero:
  #
  #   Dir.children('tmp0/')                    # => ["t.txt"]
  #   Dir.children('tmp1/')                    # => []
  #   FileUtils.ln('tmp0/t.txt', 'tmp1/t.lnk') # => 0
  #   Dir.children('tmp1/')                    # => ["t.lnk"]
  #
  # When +src+ is the path to an existing file
  # and +dest+ is the path to an existing directory,
  # creates a hard link at <tt>dest/src</tt> pointing to +src+; returns zero:
  #
  #   Dir.children('tmp2')               # => ["t.dat"]
  #   Dir.children('tmp3')               # => []
  #   FileUtils.ln('tmp2/t.dat', 'tmp3') # => 0
  #   Dir.children('tmp3')               # => ["t.dat"]
  #
  # When +src+ is an array of paths to existing files
  # and +dest+ is the path to an existing directory,
  # then for each path +target+ in +src+,
  # creates a hard link at <tt>dest/target</tt> pointing to +target+;
  # returns +src+:
  #
  #   Dir.children('tmp4/')                               # => []
  #   FileUtils.ln(['tmp0/t.txt', 'tmp2/t.dat'], 'tmp4/') # => ["tmp0/t.txt", "tmp2/t.dat"]
  #   Dir.children('tmp4/')                               # => ["t.dat", "t.txt"]
  #
  # Keyword arguments:
  #
  # - <tt>force: true</tt> - overwrites +dest+ if it exists.
  # - <tt>noop: true</tt> - does not create links.
  # - <tt>verbose: true</tt> - prints an equivalent command:
  #
  #     FileUtils.ln('tmp0/t.txt', 'tmp1/t.lnk', verbose: true)
  #     FileUtils.ln('tmp2/t.dat', 'tmp3', verbose: true)
  #     FileUtils.ln(['tmp0/t.txt', 'tmp2/t.dat'], 'tmp4/', verbose: true)
  #
  #   Output:
  #
  #     ln tmp0/t.txt tmp1/t.lnk
  #     ln tmp2/t.dat tmp3
  #     ln tmp0/t.txt tmp2/t.dat tmp4/
  #
  # Raises an exception if +dest+ is the path to an existing file
  # and keyword argument +force+ is not +true+.
  #
  # Related: FileUtils.link_entry (has different options).
  #
  def ln(src, dest, force: nil, noop: nil, verbose: nil)
    fu_output_message "ln#{force ? ' -f' : ''} #{[src,dest].flatten.join ' '}" if verbose
    return if noop
    fu_each_src_dest0(src, dest) do |s,d|
      remove_file d, true if force
      File.link s, d
    end
  end
  module_function :ln

  alias link ln
  module_function :link

  # Creates {hard links}[https://en.wikipedia.org/wiki/Hard_link].
  #
  # Arguments +src+ (a single path or an array of paths)
  # and +dest+ (a single path)
  # should be {interpretable as paths}[rdoc-ref:FileUtils@Path+Arguments].
  #
  # If +src+ is the path to a directory and +dest+ does not exist,
  # creates links +dest+ and descendents pointing to +src+ and its descendents:
  #
  #   tree('src0')
  #   # => src0
  #   #    |-- sub0
  #   #    |   |-- src0.txt
  #   #    |   `-- src1.txt
  #   #    `-- sub1
  #   #        |-- src2.txt
  #   #        `-- src3.txt
  #   File.exist?('dest0') # => false
  #   FileUtils.cp_lr('src0', 'dest0')
  #   tree('dest0')
  #   # => dest0
  #   #    |-- sub0
  #   #    |   |-- src0.txt
  #   #    |   `-- src1.txt
  #   #    `-- sub1
  #   #        |-- src2.txt
  #   #        `-- src3.txt
  #
  # If +src+ and +dest+ are both paths to directories,
  # creates links <tt>dest/src</tt> and descendents
  # pointing to +src+ and its descendents:
  #
  #   tree('src1')
  #   # => src1
  #   #    |-- sub0
  #   #    |   |-- src0.txt
  #   #    |   `-- src1.txt
  #   #    `-- sub1
  #   #        |-- src2.txt
  #   #        `-- src3.txt
  #   FileUtils.mkdir('dest1')
  #   FileUtils.cp_lr('src1', 'dest1')
  #   tree('dest1')
  #   # => dest1
  #   #    `-- src1
  #   #        |-- sub0
  #   #        |   |-- src0.txt
  #   #        |   `-- src1.txt
  #   #        `-- sub1
  #   #            |-- src2.txt
  #   #            `-- src3.txt
  #
  # If +src+ is an array of paths to entries and +dest+ is the path to a directory,
  # for each path +filepath+ in +src+, creates a link at <tt>dest/filepath</tt>
  # pointing to that path:
  #
  #   tree('src2')
  #   # => src2
  #   #    |-- sub0
  #   #    |   |-- src0.txt
  #   #    |   `-- src1.txt
  #   #    `-- sub1
  #   #        |-- src2.txt
  #   #        `-- src3.txt
  #   FileUtils.mkdir('dest2')
  #   FileUtils.cp_lr(['src2/sub0', 'src2/sub1'], 'dest2')
  #   tree('dest2')
  #   # => dest2
  #   #    |-- sub0
  #   #    |   |-- src0.txt
  #   #    |   `-- src1.txt
  #   #    `-- sub1
  #   #        |-- src2.txt
  #   #        `-- src3.txt
  #
  # Keyword arguments:
  #
  # - <tt>dereference_root: false</tt> - if +src+ is a symbolic link,
  #   does not dereference it.
  # - <tt>noop: true</tt> - does not create links.
  # - <tt>remove_destination: true</tt> - removes +dest+ before creating links.
  # - <tt>verbose: true</tt> - prints an equivalent command:
  #
  #     FileUtils.cp_lr('src0', 'dest0', noop: true, verbose: true)
  #     FileUtils.cp_lr('src1', 'dest1', noop: true, verbose: true)
  #     FileUtils.cp_lr(['src2/sub0', 'src2/sub1'], 'dest2', noop: true, verbose: true)
  #
  #   Output:
  #
  #     cp -lr src0 dest0
  #     cp -lr src1 dest1
  #     cp -lr src2/sub0 src2/sub1 dest2
  #
  # Raises an exception if +dest+ is the path to an existing file or directory
  # and keyword argument <tt>remove_destination: true</tt> is not given.
  #
  # Related: {methods for copying}[rdoc-ref:FileUtils@Copying].
  #
  def cp_lr(src, dest, noop: nil, verbose: nil,
            dereference_root: true, remove_destination: false)
    fu_output_message "cp -lr#{remove_destination ? ' --remove-destination' : ''} #{[src,dest].flatten.join ' '}" if verbose
    return if noop
    fu_each_src_dest(src, dest) do |s, d|
      link_entry s, d, dereference_root, remove_destination
    end
  end
  module_function :cp_lr

  # Creates {symbolic links}[https://en.wikipedia.org/wiki/Symbolic_link].
  #
  # Arguments +src+ (a single path or an array of paths)
  # and +dest+ (a single path)
  # should be {interpretable as paths}[rdoc-ref:FileUtils@Path+Arguments].
  #
  # If +src+ is the path to an existing file:
  #
  # - When +dest+ is the path to a non-existent file,
  #   creates a symbolic link at +dest+ pointing to +src+:
  #
  #     FileUtils.touch('src0.txt')
  #     File.exist?('dest0.txt')   # => false
  #     FileUtils.ln_s('src0.txt', 'dest0.txt')
  #     File.symlink?('dest0.txt') # => true
  #
  # - When +dest+ is the path to an existing file,
  #   creates a symbolic link at +dest+ pointing to +src+
  #   if and only if keyword argument <tt>force: true</tt> is given
  #   (raises an exception otherwise):
  #
  #     FileUtils.touch('src1.txt')
  #     FileUtils.touch('dest1.txt')
  #     FileUtils.ln_s('src1.txt', 'dest1.txt', force: true)
  #     FileTest.symlink?('dest1.txt') # => true
  #
  #     FileUtils.ln_s('src1.txt', 'dest1.txt') # Raises Errno::EEXIST.
  #
  # If +dest+ is the path to a directory,
  # creates a symbolic link at <tt>dest/src</tt> pointing to +src+:
  #
  #   FileUtils.touch('src2.txt')
  #   FileUtils.mkdir('destdir2')
  #   FileUtils.ln_s('src2.txt', 'destdir2')
  #   File.symlink?('destdir2/src2.txt') # => true
  #
  # If +src+ is an array of paths to existing files and +dest+ is a directory,
  # for each child +child+ in +src+ creates a symbolic link <tt>dest/child</tt>
  # pointing to +child+:
  #
  #   FileUtils.mkdir('srcdir3')
  #   FileUtils.touch('srcdir3/src0.txt')
  #   FileUtils.touch('srcdir3/src1.txt')
  #   FileUtils.mkdir('destdir3')
  #   FileUtils.ln_s(['srcdir3/src0.txt', 'srcdir3/src1.txt'], 'destdir3')
  #   File.symlink?('destdir3/src0.txt') # => true
  #   File.symlink?('destdir3/src1.txt') # => true
  #
  # Keyword arguments:
  #
  # - <tt>force: true</tt> - overwrites +dest+ if it exists.
  # - <tt>relative: false</tt> - create links relative to +dest+.
  # - <tt>noop: true</tt> - does not create links.
  # - <tt>verbose: true</tt> - prints an equivalent command:
  #
  #     FileUtils.ln_s('src0.txt', 'dest0.txt', noop: true, verbose: true)
  #     FileUtils.ln_s('src1.txt', 'destdir1', noop: true, verbose: true)
  #     FileUtils.ln_s('src2.txt', 'dest2.txt', force: true, noop: true, verbose: true)
  #     FileUtils.ln_s(['srcdir3/src0.txt', 'srcdir3/src1.txt'], 'destdir3', noop: true, verbose: true)
  #
  #   Output:
  #
  #     ln -s src0.txt dest0.txt
  #     ln -s src1.txt destdir1
  #     ln -sf src2.txt dest2.txt
  #     ln -s srcdir3/src0.txt srcdir3/src1.txt destdir3
  #
  # Related: FileUtils.ln_sf.
  #
  def ln_s(src, dest, force: nil, relative: false, target_directory: true, noop: nil, verbose: nil)
    if relative
      return ln_sr(src, dest, force: force, noop: noop, verbose: verbose)
    end
    fu_output_message "ln -s#{force ? 'f' : ''} #{[src,dest].flatten.join ' '}" if verbose
    return if noop
    fu_each_src_dest0(src, dest) do |s,d|
      remove_file d, true if force
      File.symlink s, d
    end
  end
  module_function :ln_s

  alias symlink ln_s
  module_function :symlink

  # Like FileUtils.ln_s, but always with keyword argument <tt>force: true</tt> given.
  #
  def ln_sf(src, dest, noop: nil, verbose: nil)
    ln_s src, dest, force: true, noop: noop, verbose: verbose
  end
  module_function :ln_sf

  # Like FileUtils.ln_s, but create links relative to +dest+.
  #
  def ln_sr(src, dest, target_directory: true, force: nil, noop: nil, verbose: nil)
    options = "#{force ? 'f' : ''}#{target_directory ? '' : 'T'}"
    dest = File.path(dest)
    srcs = Array(src)
    link = proc do |s, target_dir_p = true|
      s = File.path(s)
      if target_dir_p
        d = File.join(destdirs = dest, File.basename(s))
      else
        destdirs = File.dirname(d = dest)
      end
      destdirs = fu_split_path(File.realpath(destdirs))
      if fu_starting_path?(s)
        srcdirs = fu_split_path((File.realdirpath(s) rescue File.expand_path(s)))
        base = fu_relative_components_from(srcdirs, destdirs)
        s = File.join(*base)
      else
        srcdirs = fu_clean_components(*fu_split_path(s))
        base = fu_relative_components_from(fu_split_path(Dir.pwd), destdirs)
        while srcdirs.first&. == ".." and base.last&.!=("..") and !fu_starting_path?(base.last)
          srcdirs.shift
          base.pop
        end
        s = File.join(*base, *srcdirs)
      end
      fu_output_message "ln -s#{options} #{s} #{d}" if verbose
      next if noop
      remove_file d, true if force
      File.symlink s, d
    end
    case srcs.size
    when 0
    when 1
      link[srcs[0], target_directory && File.directory?(dest)]
    else
      srcs.each(&link)
    end
  end
  module_function :ln_sr

  # Creates {hard links}[https://en.wikipedia.org/wiki/Hard_link]; returns +nil+.
  #
  # Arguments +src+ and +dest+
  # should be {interpretable as paths}[rdoc-ref:FileUtils@Path+Arguments].
  #
  # If +src+ is the path to a file and +dest+ does not exist,
  # creates a hard link at +dest+ pointing to +src+:
  #
  #   FileUtils.touch('src0.txt')
  #   File.exist?('dest0.txt') # => false
  #   FileUtils.link_entry('src0.txt', 'dest0.txt')
  #   File.file?('dest0.txt')  # => true
  #
  # If +src+ is the path to a directory and +dest+ does not exist,
  # recursively creates hard links at +dest+ pointing to paths in +src+:
  #
  #   FileUtils.mkdir_p(['src1/dir0', 'src1/dir1'])
  #   src_file_paths = [
  #     'src1/dir0/t0.txt',
  #     'src1/dir0/t1.txt',
  #     'src1/dir1/t2.txt',
  #     'src1/dir1/t3.txt',
  #     ]
  #   FileUtils.touch(src_file_paths)
  #   File.directory?('dest1')        # => true
  #   FileUtils.link_entry('src1', 'dest1')
  #   File.file?('dest1/dir0/t0.txt') # => true
  #   File.file?('dest1/dir0/t1.txt') # => true
  #   File.file?('dest1/dir1/t2.txt') # => true
  #   File.file?('dest1/dir1/t3.txt') # => true
  #
  # Keyword arguments:
  #
  # - <tt>dereference_root: true</tt> - dereferences +src+ if it is a symbolic link.
  # - <tt>remove_destination: true</tt> - removes +dest+ before creating links.
  #
  # Raises an exception if +dest+ is the path to an existing file or directory
  # and keyword argument <tt>remove_destination: true</tt> is not given.
  #
  # Related: FileUtils.ln (has different options).
  #
  def link_entry(src, dest, dereference_root = false, remove_destination = false)
    Entry_.new(src, nil, dereference_root).traverse do |ent|
      destent = Entry_.new(dest, ent.rel, false)
      File.unlink destent.path if remove_destination && File.file?(destent.path)
      ent.link destent.path
    end
  end
  module_function :link_entry

  # Copies files.
  #
  # Arguments +src+ (a single path or an array of paths)
  # and +dest+ (a single path)
  # should be {interpretable as paths}[rdoc-ref:FileUtils@Path+Arguments].
  #
  # If +src+ is the path to a file and +dest+ is not the path to a directory,
  # copies +src+ to +dest+:
  #
  #   FileUtils.touch('src0.txt')
  #   File.exist?('dest0.txt') # => false
  #   FileUtils.cp('src0.txt', 'dest0.txt')
  #   File.file?('dest0.txt')  # => true
  #
  # If +src+ is the path to a file and +dest+ is the path to a directory,
  # copies +src+ to <tt>dest/src</tt>:
  #
  #   FileUtils.touch('src1.txt')
  #   FileUtils.mkdir('dest1')
  #   FileUtils.cp('src1.txt', 'dest1')
  #   File.file?('dest1/src1.txt') # => true
  #
  # If +src+ is an array of paths to files and +dest+ is the path to a directory,
  # copies from each +src+ to +dest+:
  #
  #   src_file_paths = ['src2.txt', 'src2.dat']
  #   FileUtils.touch(src_file_paths)
  #   FileUtils.mkdir('dest2')
  #   FileUtils.cp(src_file_paths, 'dest2')
  #   File.file?('dest2/src2.txt') # => true
  #   File.file?('dest2/src2.dat') # => true
  #
  # Keyword arguments:
  #
  # - <tt>preserve: true</tt> - preserves file times.
  # - <tt>noop: true</tt> - does not copy files.
  # - <tt>verbose: true</tt> - prints an equivalent command:
  #
  #     FileUtils.cp('src0.txt', 'dest0.txt', noop: true, verbose: true)
  #     FileUtils.cp('src1.txt', 'dest1', noop: true, verbose: true)
  #     FileUtils.cp(src_file_paths, 'dest2', noop: true, verbose: true)
  #
  #   Output:
  #
  #     cp src0.txt dest0.txt
  #     cp src1.txt dest1
  #     cp src2.txt src2.dat dest2
  #
  # Raises an exception if +src+ is a directory.
  #
  # Related: {methods for copying}[rdoc-ref:FileUtils@Copying].
  #
  def cp(src, dest, preserve: nil, noop: nil, verbose: nil)
    fu_output_message "cp#{preserve ? ' -p' : ''} #{[src,dest].flatten.join ' '}" if verbose
    return if noop
    fu_each_src_dest(src, dest) do |s, d|
      copy_file s, d, preserve
    end
  end
  module_function :cp

  alias copy cp
  module_function :copy

  # Recursively copies files.
  #
  # Arguments +src+ (a single path or an array of paths)
  # and +dest+ (a single path)
  # should be {interpretable as paths}[rdoc-ref:FileUtils@Path+Arguments].
  #
  # The mode, owner, and group are retained in the copy;
  # to change those, use FileUtils.install instead.
  #
  # If +src+ is the path to a file and +dest+ is not the path to a directory,
  # copies +src+ to +dest+:
  #
  #   FileUtils.touch('src0.txt')
  #   File.exist?('dest0.txt') # => false
  #   FileUtils.cp_r('src0.txt', 'dest0.txt')
  #   File.file?('dest0.txt')  # => true
  #
  # If +src+ is the path to a file and +dest+ is the path to a directory,
  # copies +src+ to <tt>dest/src</tt>:
  #
  #   FileUtils.touch('src1.txt')
  #   FileUtils.mkdir('dest1')
  #   FileUtils.cp_r('src1.txt', 'dest1')
  #   File.file?('dest1/src1.txt') # => true
  #
  # If +src+ is the path to a directory and +dest+ does not exist,
  # recursively copies +src+ to +dest+:
  #
  #   tree('src2')
  #   # => src2
  #   #    |-- dir0
  #   #    |   |-- src0.txt
  #   #    |   `-- src1.txt
  #   #    `-- dir1
  #   #    |-- src2.txt
  #   #    `-- src3.txt
  #   FileUtils.exist?('dest2') # => false
  #   FileUtils.cp_r('src2', 'dest2')
  #   tree('dest2')
  #   # => dest2
  #   #    |-- dir0
  #   #    |   |-- src0.txt
  #   #    |   `-- src1.txt
  #   #    `-- dir1
  #   #    |-- src2.txt
  #   #    `-- src3.txt
  #
  # If +src+ and +dest+ are paths to directories,
  # recursively copies +src+ to <tt>dest/src</tt>:
  #
  #   tree('src3')
  #   # => src3
  #   #    |-- dir0
  #   #    |   |-- src0.txt
  #   #    |   `-- src1.txt
  #   #    `-- dir1
  #   #    |-- src2.txt
  #   #    `-- src3.txt
  #   FileUtils.mkdir('dest3')
  #   FileUtils.cp_r('src3', 'dest3')
  #   tree('dest3')
  #   # => dest3
  #   #    `-- src3
  #   #      |-- dir0
  #   #      |   |-- src0.txt
  #   #      |   `-- src1.txt
  #   #      `-- dir1
  #   #          |-- src2.txt
  #   #          `-- src3.txt
  #
  # If +src+ is an array of paths and +dest+ is a directory,
  # recursively copies from each path in +src+ to +dest+;
  # the paths in +src+ may point to files and/or directories.
  #
  # Keyword arguments:
  #
  # - <tt>dereference_root: false</tt> - if +src+ is a symbolic link,
  #   does not dereference it.
  # - <tt>noop: true</tt> - does not copy files.
  # - <tt>preserve: true</tt> - preserves file times.
  # - <tt>remove_destination: true</tt> - removes +dest+ before copying files.
  # - <tt>verbose: true</tt> - prints an equivalent command:
  #
  #     FileUtils.cp_r('src0.txt', 'dest0.txt', noop: true, verbose: true)
  #     FileUtils.cp_r('src1.txt', 'dest1', noop: true, verbose: true)
  #     FileUtils.cp_r('src2', 'dest2', noop: true, verbose: true)
  #     FileUtils.cp_r('src3', 'dest3', noop: true, verbose: true)
  #
  #   Output:
  #
  #     cp -r src0.txt dest0.txt
  #     cp -r src1.txt dest1
  #     cp -r src2 dest2
  #     cp -r src3 dest3
  #
  # Raises an exception of +src+ is the path to a directory
  # and +dest+ is the path to a file.
  #
  # Related: {methods for copying}[rdoc-ref:FileUtils@Copying].
  #
  def cp_r(src, dest, preserve: nil, noop: nil, verbose: nil,
           dereference_root: true, remove_destination: nil)
    fu_output_message "cp -r#{preserve ? 'p' : ''}#{remove_destination ? ' --remove-destination' : ''} #{[src,dest].flatten.join ' '}" if verbose
    return if noop
    fu_each_src_dest(src, dest) do |s, d|
      copy_entry s, d, preserve, dereference_root, remove_destination
    end
  end
  module_function :cp_r

  # Recursively copies files from +src+ to +dest+.
  #
  # Arguments +src+ and +dest+
  # should be {interpretable as paths}[rdoc-ref:FileUtils@Path+Arguments].
  #
  # If +src+ is the path to a file, copies +src+ to +dest+:
  #
  #   FileUtils.touch('src0.txt')
  #   File.exist?('dest0.txt') # => false
  #   FileUtils.copy_entry('src0.txt', 'dest0.txt')
  #   File.file?('dest0.txt')  # => true
  #
  # If +src+ is a directory, recursively copies +src+ to +dest+:
  #
  #   tree('src1')
  #   # => src1
  #   #    |-- dir0
  #   #    |   |-- src0.txt
  #   #    |   `-- src1.txt
  #   #    `-- dir1
  #   #        |-- src2.txt
  #   #        `-- src3.txt
  #   FileUtils.copy_entry('src1', 'dest1')
  #   tree('dest1')
  #   # => dest1
  #   #    |-- dir0
  #   #    |   |-- src0.txt
  #   #    |   `-- src1.txt
  #   #    `-- dir1
  #   #        |-- src2.txt
  #   #        `-- src3.txt
  #
  # The recursive copying preserves file types for regular files,
  # directories, and symbolic links;
  # other file types (FIFO streams, device files, etc.) are not supported.
  #
  # Keyword arguments:
  #
  # - <tt>dereference_root: true</tt> - if +src+ is a symbolic link,
  #   follows the link.
  # - <tt>preserve: true</tt> - preserves file times.
  # - <tt>remove_destination: true</tt> - removes +dest+ before copying files.
  #
  # Related: {methods for copying}[rdoc-ref:FileUtils@Copying].
  #
  def copy_entry(src, dest, preserve = false, dereference_root = false, remove_destination = false)
    if dereference_root
      src = File.realpath(src)
    end

    Entry_.new(src, nil, false).wrap_traverse(proc do |ent|
      destent = Entry_.new(dest, ent.rel, false)
      File.unlink destent.path if remove_destination && (File.file?(destent.path) || File.symlink?(destent.path))
      ent.copy destent.path
    end, proc do |ent|
      destent = Entry_.new(dest, ent.rel, false)
      ent.copy_metadata destent.path if preserve
    end)
  end
  module_function :copy_entry

  # Copies file from +src+ to +dest+, which should not be directories.
  #
  # Arguments +src+ and +dest+
  # should be {interpretable as paths}[rdoc-ref:FileUtils@Path+Arguments].
  #
  # Examples:
  #
  #   FileUtils.touch('src0.txt')
  #   FileUtils.copy_file('src0.txt', 'dest0.txt')
  #   File.file?('dest0.txt') # => true
  #
  # Keyword arguments:
  #
  # - <tt>dereference: false</tt> - if +src+ is a symbolic link,
  #   does not follow the link.
  # - <tt>preserve: true</tt> - preserves file times.
  # - <tt>remove_destination: true</tt> - removes +dest+ before copying files.
  #
  # Related: {methods for copying}[rdoc-ref:FileUtils@Copying].
  #
  def copy_file(src, dest, preserve = false, dereference = true)
    ent = Entry_.new(src, nil, dereference)
    ent.copy_file dest
    ent.copy_metadata dest if preserve
  end
  module_function :copy_file

  # Copies \IO stream +src+ to \IO stream +dest+ via
  # {IO.copy_stream}[rdoc-ref:IO.copy_stream].
  #
  # Related: {methods for copying}[rdoc-ref:FileUtils@Copying].
  #
  def copy_stream(src, dest)
    IO.copy_stream(src, dest)
  end
  module_function :copy_stream

  # Moves entries.
  #
  # Arguments +src+ (a single path or an array of paths)
  # and +dest+ (a single path)
  # should be {interpretable as paths}[rdoc-ref:FileUtils@Path+Arguments].
  #
  # If +src+ and +dest+ are on different file systems,
  # first copies, then removes +src+.
  #
  # May cause a local vulnerability if not called with keyword argument
  # <tt>secure: true</tt>;
  # see {Avoiding the TOCTTOU Vulnerability}[rdoc-ref:FileUtils@Avoiding+the+TOCTTOU+Vulnerability].
  #
  # If +src+ is the path to a single file or directory and +dest+ does not exist,
  # moves +src+ to +dest+:
  #
  #   tree('src0')
  #   # => src0
  #   #    |-- src0.txt
  #   #    `-- src1.txt
  #   File.exist?('dest0') # => false
  #   FileUtils.mv('src0', 'dest0')
  #   File.exist?('src0')  # => false
  #   tree('dest0')
  #   # => dest0
  #   #    |-- src0.txt
  #   #    `-- src1.txt
  #
  # If +src+ is an array of paths to files and directories
  # and +dest+ is the path to a directory,
  # copies from each path in the array to +dest+:
  #
  #   File.file?('src1.txt') # => true
  #   tree('src1')
  #   # => src1
  #   #    |-- src.dat
  #   #    `-- src.txt
  #   Dir.empty?('dest1')    # => true
  #   FileUtils.mv(['src1.txt', 'src1'], 'dest1')
  #   tree('dest1')
  #   # => dest1
  #   #    |-- src1
  #   #    |   |-- src.dat
  #   #    |   `-- src.txt
  #   #    `-- src1.txt
  #
  # Keyword arguments:
  #
  # - <tt>force: true</tt> - if the move includes removing +src+
  #   (that is, if +src+ and +dest+ are on different file systems),
  #   ignores raised exceptions of StandardError and its descendants.
  # - <tt>noop: true</tt> - does not move files.
  # - <tt>secure: true</tt> - removes +src+ securely;
  #   see details at FileUtils.remove_entry_secure.
  # - <tt>verbose: true</tt> - prints an equivalent command:
  #
  #     FileUtils.mv('src0', 'dest0', noop: true, verbose: true)
  #     FileUtils.mv(['src1.txt', 'src1'], 'dest1', noop: true, verbose: true)
  #
  #   Output:
  #
  #     mv src0 dest0
  #     mv src1.txt src1 dest1
  #
  def mv(src, dest, force: nil, noop: nil, verbose: nil, secure: nil)
    fu_output_message "mv#{force ? ' -f' : ''} #{[src,dest].flatten.join ' '}" if verbose
    return if noop
    fu_each_src_dest(src, dest) do |s, d|
      destent = Entry_.new(d, nil, true)
      begin
        if destent.exist?
          if destent.directory?
            raise Errno::EEXIST, d
          end
        end
        begin
          File.rename s, d
        rescue Errno::EXDEV,
               Errno::EPERM # move from unencrypted to encrypted dir (ext4)
          copy_entry s, d, true
          if secure
            remove_entry_secure s, force
          else
            remove_entry s, force
          end
        end
      rescue SystemCallError
        raise unless force
      end
    end
  end
  module_function :mv

  alias move mv
  module_function :move

  # Removes entries at the paths in the given +list+
  # (a single path or an array of paths)
  # returns +list+, if it is an array, <tt>[list]</tt> otherwise.
  #
  # Argument +list+ or its elements
  # should be {interpretable as paths}[rdoc-ref:FileUtils@Path+Arguments].
  #
  # With no keyword arguments, removes files at the paths given in +list+:
  #
  #   FileUtils.touch(['src0.txt', 'src0.dat'])
  #   FileUtils.rm(['src0.dat', 'src0.txt']) # => ["src0.dat", "src0.txt"]
  #
  # Keyword arguments:
  #
  # - <tt>force: true</tt> - ignores raised exceptions of StandardError
  #   and its descendants.
  # - <tt>noop: true</tt> - does not remove files; returns +nil+.
  # - <tt>verbose: true</tt> - prints an equivalent command:
  #
  #     FileUtils.rm(['src0.dat', 'src0.txt'], noop: true, verbose: true)
  #
  #   Output:
  #
  #     rm src0.dat src0.txt
  #
  # Related: {methods for deleting}[rdoc-ref:FileUtils@Deleting].
  #
  def rm(list, force: nil, noop: nil, verbose: nil)
    list = fu_list(list)
    fu_output_message "rm#{force ? ' -f' : ''} #{list.join ' '}" if verbose
    return if noop

    list.each do |path|
      remove_file path, force
    end
  end
  module_function :rm

  alias remove rm
  module_function :remove

  # Equivalent to:
  #
  #   FileUtils.rm(list, force: true, **kwargs)
  #
  # Argument +list+ (a single path or an array of paths)
  # should be {interpretable as paths}[rdoc-ref:FileUtils@Path+Arguments].
  #
  # See FileUtils.rm for keyword arguments.
  #
  # Related: {methods for deleting}[rdoc-ref:FileUtils@Deleting].
  #
  def rm_f(list, noop: nil, verbose: nil)
    rm list, force: true, noop: noop, verbose: verbose
  end
  module_function :rm_f

  alias safe_unlink rm_f
  module_function :safe_unlink

  # Removes entries at the paths in the given +list+
  # (a single path or an array of paths);
  # returns +list+, if it is an array, <tt>[list]</tt> otherwise.
  #
  # Argument +list+ or its elements
  # should be {interpretable as paths}[rdoc-ref:FileUtils@Path+Arguments].
  #
  # May cause a local vulnerability if not called with keyword argument
  # <tt>secure: true</tt>;
  # see {Avoiding the TOCTTOU Vulnerability}[rdoc-ref:FileUtils@Avoiding+the+TOCTTOU+Vulnerability].
  #
  # For each file path, removes the file at that path:
  #
  #   FileUtils.touch(['src0.txt', 'src0.dat'])
  #   FileUtils.rm_r(['src0.dat', 'src0.txt'])
  #   File.exist?('src0.txt') # => false
  #   File.exist?('src0.dat') # => false
  #
  # For each directory path, recursively removes files and directories:
  #
  #   tree('src1')
  #   # => src1
  #   #    |-- dir0
  #   #    |   |-- src0.txt
  #   #    |   `-- src1.txt
  #   #    `-- dir1
  #   #        |-- src2.txt
  #   #        `-- src3.txt
  #   FileUtils.rm_r('src1')
  #   File.exist?('src1') # => false
  #
  # Keyword arguments:
  #
  # - <tt>force: true</tt> - ignores raised exceptions of StandardError
  #   and its descendants.
  # - <tt>noop: true</tt> - does not remove entries; returns +nil+.
  # - <tt>secure: true</tt> - removes +src+ securely;
  #   see details at FileUtils.remove_entry_secure.
  # - <tt>verbose: true</tt> - prints an equivalent command:
  #
  #     FileUtils.rm_r(['src0.dat', 'src0.txt'], noop: true, verbose: true)
  #     FileUtils.rm_r('src1', noop: true, verbose: true)
  #
  #   Output:
  #
  #     rm -r src0.dat src0.txt
  #     rm -r src1
  #
  # Related: {methods for deleting}[rdoc-ref:FileUtils@Deleting].
  #
  def rm_r(list, force: nil, noop: nil, verbose: nil, secure: nil)
    list = fu_list(list)
    fu_output_message "rm -r#{force ? 'f' : ''} #{list.join ' '}" if verbose
    return if noop
    list.each do |path|
      if secure
        remove_entry_secure path, force
      else
        remove_entry path, force
      end
    end
  end
  module_function :rm_r

  # Equivalent to:
  #
  #   FileUtils.rm_r(list, force: true, **kwargs)
  #
  # Argument +list+ or its elements
  # should be {interpretable as paths}[rdoc-ref:FileUtils@Path+Arguments].
  #
  # May cause a local vulnerability if not called with keyword argument
  # <tt>secure: true</tt>;
  # see {Avoiding the TOCTTOU Vulnerability}[rdoc-ref:FileUtils@Avoiding+the+TOCTTOU+Vulnerability].
  #
  # See FileUtils.rm_r for keyword arguments.
  #
  # Related: {methods for deleting}[rdoc-ref:FileUtils@Deleting].
  #
  def rm_rf(list, noop: nil, verbose: nil, secure: nil)
    rm_r list, force: true, noop: noop, verbose: verbose, secure: secure
  end
  module_function :rm_rf

  alias rmtree rm_rf
  module_function :rmtree

  # Securely removes the entry given by +path+,
  # which should be the entry for a regular file, a symbolic link,
  # or a directory.
  #
  # Argument +path+
  # should be {interpretable as a path}[rdoc-ref:FileUtils@Path+Arguments].
  #
  # Avoids a local vulnerability that can exist in certain circumstances;
  # see {Avoiding the TOCTTOU Vulnerability}[rdoc-ref:FileUtils@Avoiding+the+TOCTTOU+Vulnerability].
  #
  # Optional argument +force+ specifies whether to ignore
  # raised exceptions of StandardError and its descendants.
  #
  # Related: {methods for deleting}[rdoc-ref:FileUtils@Deleting].
  #
  def remove_entry_secure(path, force = false)
    unless fu_have_symlink?
      remove_entry path, force
      return
    end
    fullpath = File.expand_path(path)
    st = File.lstat(fullpath)
    unless st.directory?
      File.unlink fullpath
      return
    end
    # is a directory.
    parent_st = File.stat(File.dirname(fullpath))
    unless parent_st.world_writable?
      remove_entry path, force
      return
    end
    unless parent_st.sticky?
      raise ArgumentError, "parent directory is world writable, FileUtils#remove_entry_secure does not work; abort: #{path.inspect} (parent directory mode #{'%o' % parent_st.mode})"
    end

    # freeze tree root
    euid = Process.euid
    dot_file = fullpath + "/."
    begin
      File.open(dot_file) {|f|
        unless fu_stat_identical_entry?(st, f.stat)
          # symlink (TOC-to-TOU attack?)
          File.unlink fullpath
          return
        end
        f.chown euid, -1
        f.chmod 0700
      }
    rescue Errno::EISDIR # JRuby in non-native mode can't open files as dirs
      File.lstat(dot_file).tap {|fstat|
        unless fu_stat_identical_entry?(st, fstat)
          # symlink (TOC-to-TOU attack?)
          File.unlink fullpath
          return
        end
        File.chown euid, -1, dot_file
        File.chmod 0700, dot_file
      }
    end

    unless fu_stat_identical_entry?(st, File.lstat(fullpath))
      # TOC-to-TOU attack?
      File.unlink fullpath
      return
    end

    # ---- tree root is frozen ----
    root = Entry_.new(path)
    root.preorder_traverse do |ent|
      if ent.directory?
        ent.chown euid, -1
        ent.chmod 0700
      end
    end
    root.postorder_traverse do |ent|
      begin
        ent.remove
      rescue
        raise unless force
      end
    end
  rescue
    raise unless force
  end
  module_function :remove_entry_secure

  def fu_have_symlink?   #:nodoc:
    File.symlink nil, nil
  rescue NotImplementedError
    return false
  rescue TypeError
    return true
  end
  private_module_function :fu_have_symlink?

  def fu_stat_identical_entry?(a, b)   #:nodoc:
    a.dev == b.dev and a.ino == b.ino
  end
  private_module_function :fu_stat_identical_entry?

  # Removes the entry given by +path+,
  # which should be the entry for a regular file, a symbolic link,
  # or a directory.
  #
  # Argument +path+
  # should be {interpretable as a path}[rdoc-ref:FileUtils@Path+Arguments].
  #
  # Optional argument +force+ specifies whether to ignore
  # raised exceptions of StandardError and its descendants.
  #
  # Related: FileUtils.remove_entry_secure.
  #
  def remove_entry(path, force = false)
    Entry_.new(path).postorder_traverse do |ent|
      begin
        ent.remove
      rescue
        raise unless force
      end
    end
  rescue
    raise unless force
  end
  module_function :remove_entry

  # Removes the file entry given by +path+,
  # which should be the entry for a regular file or a symbolic link.
  #
  # Argument +path+
  # should be {interpretable as a path}[rdoc-ref:FileUtils@Path+Arguments].
  #
  # Optional argument +force+ specifies whether to ignore
  # raised exceptions of StandardError and its descendants.
  #
  # Related: {methods for deleting}[rdoc-ref:FileUtils@Deleting].
  #
  def remove_file(path, force = false)
    Entry_.new(path).remove_file
  rescue
    raise unless force
  end
  module_function :remove_file

  # Recursively removes the directory entry given by +path+,
  # which should be the entry for a regular file, a symbolic link,
  # or a directory.
  #
  # Argument +path+
  # should be {interpretable as a path}[rdoc-ref:FileUtils@Path+Arguments].
  #
  # Optional argument +force+ specifies whether to ignore
  # raised exceptions of StandardError and its descendants.
  #
  # Related: {methods for deleting}[rdoc-ref:FileUtils@Deleting].
  #
  def remove_dir(path, force = false)
    remove_entry path, force   # FIXME?? check if it is a directory
  end
  module_function :remove_dir

  # Returns +true+ if the contents of files +a+ and +b+ are identical,
  # +false+ otherwise.
  #
  # Arguments +a+ and +b+
  # should be {interpretable as a path}[rdoc-ref:FileUtils@Path+Arguments].
  #
  # FileUtils.identical? and FileUtils.cmp are aliases for FileUtils.compare_file.
  #
  # Related: FileUtils.compare_stream.
  #
  def compare_file(a, b)
    return false unless File.size(a) == File.size(b)
    File.open(a, 'rb') {|fa|
      File.open(b, 'rb') {|fb|
        return compare_stream(fa, fb)
      }
    }
  end
  module_function :compare_file

  alias identical? compare_file
  alias cmp compare_file
  module_function :identical?
  module_function :cmp

  # Returns +true+ if the contents of streams +a+ and +b+ are identical,
  # +false+ otherwise.
  #
  # Arguments +a+ and +b+
  # should be {interpretable as a path}[rdoc-ref:FileUtils@Path+Arguments].
  #
  # Related: FileUtils.compare_file.
  #
  def compare_stream(a, b)
    bsize = fu_stream_blksize(a, b)

    sa = String.new(capacity: bsize)
    sb = String.new(capacity: bsize)

    begin
      a.read(bsize, sa)
      b.read(bsize, sb)
      return true if sa.empty? && sb.empty?
    end while sa == sb
    false
  end
  module_function :compare_stream

  # Copies a file entry.
  # See {install(1)}[https://man7.org/linux/man-pages/man1/install.1.html].
  #
  # Arguments +src+ (a single path or an array of paths)
  # and +dest+ (a single path)
  # should be {interpretable as paths}[rdoc-ref:FileUtils@Path+Arguments];
  #
  # If the entry at +dest+ does not exist, copies from +src+ to +dest+:
  #
  #   File.read('src0.txt')    # => "aaa\n"
  #   File.exist?('dest0.txt') # => false
  #   FileUtils.install('src0.txt', 'dest0.txt')
  #   File.read('dest0.txt')   # => "aaa\n"
  #
  # If +dest+ is a file entry, copies from +src+ to +dest+, overwriting:
  #
  #   File.read('src1.txt')  # => "aaa\n"
  #   File.read('dest1.txt') # => "bbb\n"
  #   FileUtils.install('src1.txt', 'dest1.txt')
  #   File.read('dest1.txt') # => "aaa\n"
  #
  # If +dest+ is a directory entry, copies from +src+ to <tt>dest/src</tt>,
  # overwriting if necessary:
  #
  #   File.read('src2.txt')       # => "aaa\n"
  #   File.read('dest2/src2.txt') # => "bbb\n"
  #   FileUtils.install('src2.txt', 'dest2')
  #   File.read('dest2/src2.txt') # => "aaa\n"
  #
  # If +src+ is an array of paths and +dest+ points to a directory,
  # copies each path +path+ in +src+ to <tt>dest/path</tt>:
  #
  #   File.file?('src3.txt') # => true
  #   File.file?('src3.dat') # => true
  #   FileUtils.mkdir('dest3')
  #   FileUtils.install(['src3.txt', 'src3.dat'], 'dest3')
  #   File.file?('dest3/src3.txt') # => true
  #   File.file?('dest3/src3.dat') # => true
  #
  # Keyword arguments:
  #
  # - <tt>group: <i>group</i></tt> - changes the group if not +nil+,
  #   using {File.chown}[rdoc-ref:File.chown].
  # - <tt>mode: <i>permissions</i></tt> - changes the permissions.
  #   using {File.chmod}[rdoc-ref:File.chmod].
  # - <tt>noop: true</tt> - does not copy entries; returns +nil+.
  # - <tt>owner: <i>owner</i></tt> - changes the owner if not +nil+,
  #   using {File.chown}[rdoc-ref:File.chown].
  # - <tt>preserve: true</tt> - preserve timestamps
  #   using {File.utime}[rdoc-ref:File.utime].
  # - <tt>verbose: true</tt> - prints an equivalent command:
  #
  #     FileUtils.install('src0.txt', 'dest0.txt', noop: true, verbose: true)
  #     FileUtils.install('src1.txt', 'dest1.txt', noop: true, verbose: true)
  #     FileUtils.install('src2.txt', 'dest2', noop: true, verbose: true)
  #
  #   Output:
  #
  #     install -c src0.txt dest0.txt
  #     install -c src1.txt dest1.txt
  #     install -c src2.txt dest2
  #
  # Related: {methods for copying}[rdoc-ref:FileUtils@Copying].
  #
  def install(src, dest, mode: nil, owner: nil, group: nil, preserve: nil,
              noop: nil, verbose: nil)
    if verbose
      msg = +"install -c"
      msg << ' -p' if preserve
      msg << ' -m ' << mode_to_s(mode) if mode
      msg << " -o #{owner}" if owner
      msg << " -g #{group}" if group
      msg << ' ' << [src,dest].flatten.join(' ')
      fu_output_message msg
    end
    return if noop
    uid = fu_get_uid(owner)
    gid = fu_get_gid(group)
    fu_each_src_dest(src, dest) do |s, d|
      st = File.stat(s)
      unless File.exist?(d) and compare_file(s, d)
        remove_file d, true
        if d.end_with?('/')
          mkdir_p d
          copy_file s, d + File.basename(s)
        else
          mkdir_p File.expand_path('..', d)
          copy_file s, d
        end
        File.utime st.atime, st.mtime, d if preserve
        File.chmod fu_mode(mode, st), d if mode
        File.chown uid, gid, d if uid or gid
      end
    end
  end
  module_function :install

  def user_mask(target)  #:nodoc:
    target.each_char.inject(0) do |mask, chr|
      case chr
      when "u"
        mask | 04700
      when "g"
        mask | 02070
      when "o"
        mask | 01007
      when "a"
        mask | 07777
      else
        raise ArgumentError, "invalid `who' symbol in file mode: #{chr}"
      end
    end
  end
  private_module_function :user_mask

  def apply_mask(mode, user_mask, op, mode_mask)   #:nodoc:
    case op
    when '='
      (mode & ~user_mask) | (user_mask & mode_mask)
    when '+'
      mode | (user_mask & mode_mask)
    when '-'
      mode & ~(user_mask & mode_mask)
    end
  end
  private_module_function :apply_mask

  def symbolic_modes_to_i(mode_sym, path)  #:nodoc:
    path = File.stat(path) unless File::Stat === path
    mode = path.mode
    mode_sym.split(/,/).inject(mode & 07777) do |current_mode, clause|
      target, *actions = clause.split(/([=+-])/)
      raise ArgumentError, "invalid file mode: #{mode_sym}" if actions.empty?
      target = 'a' if target.empty?
      user_mask = user_mask(target)
      actions.each_slice(2) do |op, perm|
        need_apply = op == '='
        mode_mask = (perm || '').each_char.inject(0) do |mask, chr|
          case chr
          when "r"
            mask | 0444
          when "w"
            mask | 0222
          when "x"
            mask | 0111
          when "X"
            if path.directory?
              mask | 0111
            else
              mask
            end
          when "s"
            mask | 06000
          when "t"
            mask | 01000
          when "u", "g", "o"
            if mask.nonzero?
              current_mode = apply_mask(current_mode, user_mask, op, mask)
            end
            need_apply = false
            copy_mask = user_mask(chr)
            (current_mode & copy_mask) / (copy_mask & 0111) * (user_mask & 0111)
          else
            raise ArgumentError, "invalid `perm' symbol in file mode: #{chr}"
          end
        end

        if mode_mask.nonzero? || need_apply
          current_mode = apply_mask(current_mode, user_mask, op, mode_mask)
        end
      end
      current_mode
    end
  end
  private_module_function :symbolic_modes_to_i

  def fu_mode(mode, path)  #:nodoc:
    mode.is_a?(String) ? symbolic_modes_to_i(mode, path) : mode
  end
  private_module_function :fu_mode

  def mode_to_s(mode)  #:nodoc:
    mode.is_a?(String) ? mode : "%o" % mode
  end
  private_module_function :mode_to_s

  # Changes permissions on the entries at the paths given in +list+
  # (a single path or an array of paths)
  # to the permissions given by +mode+;
  # returns +list+ if it is an array, <tt>[list]</tt> otherwise:
  #
  # - Modifies each entry that is a regular file using
  #   {File.chmod}[rdoc-ref:File.chmod].
  # - Modifies each entry that is a symbolic link using
  #   {File.lchmod}[rdoc-ref:File.lchmod].
  #
  # Argument +list+ or its elements
  # should be {interpretable as paths}[rdoc-ref:FileUtils@Path+Arguments].
  #
  # Argument +mode+ may be either an integer or a string:
  #
  # - \Integer +mode+: represents the permission bits to be set:
  #
  #     FileUtils.chmod(0755, 'src0.txt')
  #     FileUtils.chmod(0644, ['src0.txt', 'src0.dat'])
  #
  # - \String +mode+: represents the permissions to be set:
  #
  #   The string is of the form <tt>[targets][[operator][perms[,perms]]</tt>, where:
  #
  #   - +targets+ may be any combination of these letters:
  #
  #     - <tt>'u'</tt>: permissions apply to the file's owner.
  #     - <tt>'g'</tt>: permissions apply to users in the file's group.
  #     - <tt>'o'</tt>: permissions apply to other users not in the file's group.
  #     - <tt>'a'</tt> (the default): permissions apply to all users.
  #
  #   - +operator+ may be one of these letters:
  #
  #     - <tt>'+'</tt>: adds permissions.
  #     - <tt>'-'</tt>: removes permissions.
  #     - <tt>'='</tt>: sets (replaces) permissions.
  #
  #   - +perms+ (may be repeated, with separating commas)
  #     may be any combination of these letters:
  #
  #     - <tt>'r'</tt>: Read.
  #     - <tt>'w'</tt>: Write.
  #     - <tt>'x'</tt>: Execute (search, for a directory).
  #     - <tt>'X'</tt>: Search (for a directories only;
  #       must be used with <tt>'+'</tt>)
  #     - <tt>'s'</tt>: Uid or gid.
  #     - <tt>'t'</tt>: Sticky bit.
  #
  #   Examples:
  #
  #     FileUtils.chmod('u=wrx,go=rx', 'src1.txt')
  #     FileUtils.chmod('u=wrx,go=rx', '/usr/bin/ruby')
  #
  # Keyword arguments:
  #
  # - <tt>noop: true</tt> - does not change permissions; returns +nil+.
  # - <tt>verbose: true</tt> - prints an equivalent command:
  #
  #     FileUtils.chmod(0755, 'src0.txt', noop: true, verbose: true)
  #     FileUtils.chmod(0644, ['src0.txt', 'src0.dat'], noop: true, verbose: true)
  #     FileUtils.chmod('u=wrx,go=rx', 'src1.txt', noop: true, verbose: true)
  #     FileUtils.chmod('u=wrx,go=rx', '/usr/bin/ruby', noop: true, verbose: true)
  #
  #   Output:
  #
  #     chmod 755 src0.txt
  #     chmod 644 src0.txt src0.dat
  #     chmod u=wrx,go=rx src1.txt
  #     chmod u=wrx,go=rx /usr/bin/ruby
  #
  # Related: FileUtils.chmod_R.
  #
  def chmod(mode, list, noop: nil, verbose: nil)
    list = fu_list(list)
    fu_output_message sprintf('chmod %s %s', mode_to_s(mode), list.join(' ')) if verbose
    return if noop
    list.each do |path|
      Entry_.new(path).chmod(fu_mode(mode, path))
    end
  end
  module_function :chmod

  # Like FileUtils.chmod, but changes permissions recursively.
  #
  def chmod_R(mode, list, noop: nil, verbose: nil, force: nil)
    list = fu_list(list)
    fu_output_message sprintf('chmod -R%s %s %s',
                              (force ? 'f' : ''),
                              mode_to_s(mode), list.join(' ')) if verbose
    return if noop
    list.each do |root|
      Entry_.new(root).traverse do |ent|
        begin
          ent.chmod(fu_mode(mode, ent.path))
        rescue
          raise unless force
        end
      end
    end
  end
  module_function :chmod_R

  # Changes the owner and group on the entries at the paths given in +list+
  # (a single path or an array of paths)
  # to the given +user+ and +group+;
  # returns +list+ if it is an array, <tt>[list]</tt> otherwise:
  #
  # - Modifies each entry that is a regular file using
  #   {File.chown}[rdoc-ref:File.chown].
  # - Modifies each entry that is a symbolic link using
  #   {File.lchown}[rdoc-ref:File.lchown].
  #
  # Argument +list+ or its elements
  # should be {interpretable as paths}[rdoc-ref:FileUtils@Path+Arguments].
  #
  # User and group:
  #
  # - Argument +user+ may be a user name or a user id;
  #   if +nil+ or +-1+, the user is not changed.
  # - Argument +group+ may be a group name or a group id;
  #   if +nil+ or +-1+, the group is not changed.
  # - The user must be a member of the group.
  #
  # Examples:
  #
  #   # One path.
  #   # User and group as string names.
  #   File.stat('src0.txt').uid # => 1004
  #   File.stat('src0.txt').gid # => 1004
  #   FileUtils.chown('user2', 'group1', 'src0.txt')
  #   File.stat('src0.txt').uid # => 1006
  #   File.stat('src0.txt').gid # => 1005
  #
  #   # User and group as uid and gid.
  #   FileUtils.chown(1004, 1004, 'src0.txt')
  #   File.stat('src0.txt').uid # => 1004
  #   File.stat('src0.txt').gid # => 1004
  #
  #   # Array of paths.
  #   FileUtils.chown(1006, 1005, ['src0.txt', 'src0.dat'])
  #
  #   # Directory (not recursive).
  #   FileUtils.chown('user2', 'group1', '.')
  #
  # Keyword arguments:
  #
  # - <tt>noop: true</tt> - does not change permissions; returns +nil+.
  # - <tt>verbose: true</tt> - prints an equivalent command:
  #
  #     FileUtils.chown('user2', 'group1', 'src0.txt', noop: true, verbose: true)
  #     FileUtils.chown(1004, 1004, 'src0.txt', noop: true, verbose: true)
  #     FileUtils.chown(1006, 1005, ['src0.txt', 'src0.dat'], noop: true, verbose: true)
  #     FileUtils.chown('user2', 'group1', path, noop: true, verbose: true)
  #     FileUtils.chown('user2', 'group1', '.', noop: true, verbose: true)
  #
  #   Output:
  #
  #     chown user2:group1 src0.txt
  #     chown 1004:1004 src0.txt
  #     chown 1006:1005 src0.txt src0.dat
  #     chown user2:group1 src0.txt
  #     chown user2:group1 .
  #
  # Related: FileUtils.chown_R.
  #
  def chown(user, group, list, noop: nil, verbose: nil)
    list = fu_list(list)
    fu_output_message sprintf('chown %s %s',
                              (group ? "#{user}:#{group}" : user || ':'),
                              list.join(' ')) if verbose
    return if noop
    uid = fu_get_uid(user)
    gid = fu_get_gid(group)
    list.each do |path|
      Entry_.new(path).chown uid, gid
    end
  end
  module_function :chown

  # Like FileUtils.chown, but changes owner and group recursively.
  #
  def chown_R(user, group, list, noop: nil, verbose: nil, force: nil)
    list = fu_list(list)
    fu_output_message sprintf('chown -R%s %s %s',
                              (force ? 'f' : ''),
                              (group ? "#{user}:#{group}" : user || ':'),
                              list.join(' ')) if verbose
    return if noop
    uid = fu_get_uid(user)
    gid = fu_get_gid(group)
    list.each do |root|
      Entry_.new(root).traverse do |ent|
        begin
          ent.chown uid, gid
        rescue
          raise unless force
        end
      end
    end
  end
  module_function :chown_R

  def fu_get_uid(user)   #:nodoc:
    return nil unless user
    case user
    when Integer
      user
    when /\A\d+\z/
      user.to_i
    else
      require 'etc'
      Etc.getpwnam(user) ? Etc.getpwnam(user).uid : nil
    end
  end
  private_module_function :fu_get_uid

  def fu_get_gid(group)   #:nodoc:
    return nil unless group
    case group
    when Integer
      group
    when /\A\d+\z/
      group.to_i
    else
      require 'etc'
      Etc.getgrnam(group) ? Etc.getgrnam(group).gid : nil
    end
  end
  private_module_function :fu_get_gid

  # Updates modification times (mtime) and access times (atime)
  # of the entries given by the paths in +list+
  # (a single path or an array of paths);
  # returns +list+ if it is an array, <tt>[list]</tt> otherwise.
  #
  # By default, creates an empty file for any path to a non-existent entry;
  # use keyword argument +nocreate+ to raise an exception instead.
  #
  # Argument +list+ or its elements
  # should be {interpretable as paths}[rdoc-ref:FileUtils@Path+Arguments].
  #
  # Examples:
  #
  #   # Single path.
  #   f = File.new('src0.txt') # Existing file.
  #   f.atime # => 2022-06-10 11:11:21.200277 -0700
  #   f.mtime # => 2022-06-10 11:11:21.200277 -0700
  #   FileUtils.touch('src0.txt')
  #   f = File.new('src0.txt')
  #   f.atime # => 2022-06-11 08:28:09.8185343 -0700
  #   f.mtime # => 2022-06-11 08:28:09.8185343 -0700
  #
  #   # Array of paths.
  #   FileUtils.touch(['src0.txt', 'src0.dat'])
  #
  # Keyword arguments:
  #
  # - <tt>mtime: <i>time</i></tt> - sets the entry's mtime to the given time,
  #   instead of the current time.
  # - <tt>nocreate: true</tt> - raises an exception if the entry does not exist.
  # - <tt>noop: true</tt> - does not touch entries; returns +nil+.
  # - <tt>verbose: true</tt> - prints an equivalent command:
  #
  #     FileUtils.touch('src0.txt', noop: true, verbose: true)
  #     FileUtils.touch(['src0.txt', 'src0.dat'], noop: true, verbose: true)
  #     FileUtils.touch(path, noop: true, verbose: true)
  #
  #   Output:
  #
  #     touch src0.txt
  #     touch src0.txt src0.dat
  #     touch src0.txt
  #
  # Related: FileUtils.uptodate?.
  #
  def touch(list, noop: nil, verbose: nil, mtime: nil, nocreate: nil)
    list = fu_list(list)
    t = mtime
    if verbose
      fu_output_message "touch #{nocreate ? '-c ' : ''}#{t ? t.strftime('-t %Y%m%d%H%M.%S ') : ''}#{list.join ' '}"
    end
    return if noop
    list.each do |path|
      created = nocreate
      begin
        File.utime(t, t, path)
      rescue Errno::ENOENT
        raise if created
        File.open(path, 'a') {
          ;
        }
        created = true
        retry if t
      end
    end
  end
  module_function :touch

  private

  module StreamUtils_
    private

    case (defined?(::RbConfig) ? ::RbConfig::CONFIG['host_os'] : ::RUBY_PLATFORM)
    when /mswin|mingw/
      def fu_windows?; true end
    else
      def fu_windows?; false end
    end

    def fu_copy_stream0(src, dest, blksize = nil)   #:nodoc:
      IO.copy_stream(src, dest)
    end

    def fu_stream_blksize(*streams)
      streams.each do |s|
        next unless s.respond_to?(:stat)
        size = fu_blksize(s.stat)
        return size if size
      end
      fu_default_blksize()
    end

    def fu_blksize(st)
      s = st.blksize
      return nil unless s
      return nil if s == 0
      s
    end

    def fu_default_blksize
      1024
    end
  end

  include StreamUtils_
  extend StreamUtils_

  class Entry_   #:nodoc: internal use only
    include StreamUtils_

    def initialize(a, b = nil, deref = false)
      @prefix = @rel = @path = nil
      if b
        @prefix = a
        @rel = b
      else
        @path = a
      end
      @deref = deref
      @stat = nil
      @lstat = nil
    end

    def inspect
      "\#<#{self.class} #{path()}>"
    end

    def path
      if @path
        File.path(@path)
      else
        join(@prefix, @rel)
      end
    end

    def prefix
      @prefix || @path
    end

    def rel
      @rel
    end

    def dereference?
      @deref
    end

    def exist?
      begin
        lstat
        true
      rescue Errno::ENOENT
        false
      end
    end

    def file?
      s = lstat!
      s and s.file?
    end

    def directory?
      s = lstat!
      s and s.directory?
    end

    def symlink?
      s = lstat!
      s and s.symlink?
    end

    def chardev?
      s = lstat!
      s and s.chardev?
    end

    def blockdev?
      s = lstat!
      s and s.blockdev?
    end

    def socket?
      s = lstat!
      s and s.socket?
    end

    def pipe?
      s = lstat!
      s and s.pipe?
    end

    S_IF_DOOR = 0xD000

    def door?
      s = lstat!
      s and (s.mode & 0xF000 == S_IF_DOOR)
    end

    def entries
      opts = {}
      opts[:encoding] = fu_windows? ? ::Encoding::UTF_8 : path.encoding

      files = Dir.children(path, **opts)

      untaint = RUBY_VERSION < '2.7'
      files.map {|n| Entry_.new(prefix(), join(rel(), untaint ? n.untaint : n)) }
    end

    def stat
      return @stat if @stat
      if lstat() and lstat().symlink?
        @stat = File.stat(path())
      else
        @stat = lstat()
      end
      @stat
    end

    def stat!
      return @stat if @stat
      if lstat! and lstat!.symlink?
        @stat = File.stat(path())
      else
        @stat = lstat!
      end
      @stat
    rescue SystemCallError
      nil
    end

    def lstat
      if dereference?
        @lstat ||= File.stat(path())
      else
        @lstat ||= File.lstat(path())
      end
    end

    def lstat!
      lstat()
    rescue SystemCallError
      nil
    end

    def chmod(mode)
      if symlink?
        File.lchmod mode, path() if have_lchmod?
      else
        File.chmod mode, path()
      end
    rescue Errno::EOPNOTSUPP
    end

    def chown(uid, gid)
      if symlink?
        File.lchown uid, gid, path() if have_lchown?
      else
        File.chown uid, gid, path()
      end
    end

    def link(dest)
      case
      when directory?
        if !File.exist?(dest) and descendant_directory?(dest, path)
          raise ArgumentError, "cannot link directory %s to itself %s" % [path, dest]
        end
        begin
          Dir.mkdir dest
        rescue
          raise unless File.directory?(dest)
        end
      else
        File.link path(), dest
      end
    end

    def copy(dest)
      lstat
      case
      when file?
        copy_file dest
      when directory?
        if !File.exist?(dest) and descendant_directory?(dest, path)
          raise ArgumentError, "cannot copy directory %s to itself %s" % [path, dest]
        end
        begin
          Dir.mkdir dest
        rescue
          raise unless File.directory?(dest)
        end
      when symlink?
        File.symlink File.readlink(path()), dest
      when chardev?, blockdev?
        raise "cannot handle device file"
      when socket?
        begin
          require 'socket'
        rescue LoadError
          raise "cannot handle socket"
        else
          raise "cannot handle socket" unless defined?(UNIXServer)
        end
        UNIXServer.new(dest).close
        File.chmod lstat().mode, dest
      when pipe?
        raise "cannot handle FIFO" unless File.respond_to?(:mkfifo)
        File.mkfifo dest, lstat().mode
      when door?
        raise "cannot handle door: #{path()}"
      else
        raise "unknown file type: #{path()}"
      end
    end

    def copy_file(dest)
      File.open(path()) do |s|
        File.open(dest, 'wb', s.stat.mode) do |f|
          IO.copy_stream(s, f)
        end
      end
    end

    def copy_metadata(path)
      st = lstat()
      if !st.symlink?
        File.utime st.atime, st.mtime, path
      end
      mode = st.mode
      begin
        if st.symlink?
          begin
            File.lchown st.uid, st.gid, path
          rescue NotImplementedError
          end
        else
          File.chown st.uid, st.gid, path
        end
      rescue Errno::EPERM, Errno::EACCES
        # clear setuid/setgid
        mode &= 01777
      end
      if st.symlink?
        begin
          File.lchmod mode, path
        rescue NotImplementedError, Errno::EOPNOTSUPP
        end
      else
        File.chmod mode, path
      end
    end

    def remove
      if directory?
        remove_dir1
      else
        remove_file
      end
    end

    def remove_dir1
      platform_support {
        Dir.rmdir path().chomp(?/)
      }
    end

    def remove_file
      platform_support {
        File.unlink path
      }
    end

    def platform_support
      return yield unless fu_windows?
      first_time_p = true
      begin
        yield
      rescue Errno::ENOENT
        raise
      rescue => err
        if first_time_p
          first_time_p = false
          begin
            File.chmod 0700, path()   # Windows does not have symlink
            retry
          rescue SystemCallError
          end
        end
        raise err
      end
    end

    def preorder_traverse
      stack = [self]
      while ent = stack.pop
        yield ent
        stack.concat ent.entries.reverse if ent.directory?
      end
    end

    alias traverse preorder_traverse

    def postorder_traverse
      if directory?
        begin
          children = entries()
        rescue Errno::EACCES
          # Failed to get the list of children.
          # Assuming there is no children, try to process the parent directory.
          yield self
          return
        end

        children.each do |ent|
          ent.postorder_traverse do |e|
            yield e
          end
        end
      end
      yield self
    end

    def wrap_traverse(pre, post)
      pre.call self
      if directory?
        entries.each do |ent|
          ent.wrap_traverse pre, post
        end
      end
      post.call self
    end

    private

    @@fileutils_rb_have_lchmod = nil

    def have_lchmod?
      # This is not MT-safe, but it does not matter.
      if @@fileutils_rb_have_lchmod == nil
        @@fileutils_rb_have_lchmod = check_have_lchmod?
      end
      @@fileutils_rb_have_lchmod
    end

    def check_have_lchmod?
      return false unless File.respond_to?(:lchmod)
      File.lchmod 0
      return true
    rescue NotImplementedError
      return false
    end

    @@fileutils_rb_have_lchown = nil

    def have_lchown?
      # This is not MT-safe, but it does not matter.
      if @@fileutils_rb_have_lchown == nil
        @@fileutils_rb_have_lchown = check_have_lchown?
      end
      @@fileutils_rb_have_lchown
    end

    def check_have_lchown?
      return false unless File.respond_to?(:lchown)
      File.lchown nil, nil
      return true
    rescue NotImplementedError
      return false
    end

    def join(dir, base)
      return File.path(dir) if not base or base == '.'
      return File.path(base) if not dir or dir == '.'
      begin
        File.join(dir, base)
      rescue EncodingError
        if fu_windows?
          File.join(dir.encode(::Encoding::UTF_8), base.encode(::Encoding::UTF_8))
        else
          raise
        end
      end
    end

    if File::ALT_SEPARATOR
      DIRECTORY_TERM = "(?=[/#{Regexp.quote(File::ALT_SEPARATOR)}]|\\z)"
    else
      DIRECTORY_TERM = "(?=/|\\z)"
    end

    def descendant_directory?(descendant, ascendant)
      if File::FNM_SYSCASE.nonzero?
        File.expand_path(File.dirname(descendant)).casecmp(File.expand_path(ascendant)) == 0
      else
        File.expand_path(File.dirname(descendant)) == File.expand_path(ascendant)
      end
    end
  end   # class Entry_

  def fu_list(arg)   #:nodoc:
    [arg].flatten.map {|path| File.path(path) }
  end
  private_module_function :fu_list

  def fu_each_src_dest(src, dest)   #:nodoc:
    fu_each_src_dest0(src, dest) do |s, d|
      raise ArgumentError, "same file: #{s} and #{d}" if fu_same?(s, d)
      yield s, d
    end
  end
  private_module_function :fu_each_src_dest

  def fu_each_src_dest0(src, dest, target_directory = true)   #:nodoc:
    if tmp = Array.try_convert(src)
      tmp.each do |s|
        s = File.path(s)
        yield s, (target_directory ? File.join(dest, File.basename(s)) : dest)
      end
    else
      src = File.path(src)
      if target_directory and File.directory?(dest)
        yield src, File.join(dest, File.basename(src))
      else
        yield src, File.path(dest)
      end
    end
  end
  private_module_function :fu_each_src_dest0

  def fu_same?(a, b)   #:nodoc:
    File.identical?(a, b)
  end
  private_module_function :fu_same?

  def fu_output_message(msg)   #:nodoc:
    output = @fileutils_output if defined?(@fileutils_output)
    output ||= $stdout
    if defined?(@fileutils_label)
      msg = @fileutils_label + msg
    end
    output.puts msg
  end
  private_module_function :fu_output_message

  def fu_split_path(path)
    path = File.path(path)
    list = []
    until (parent, base = File.split(path); parent == path or parent == ".")
      list << base
      path = parent
    end
    list << path
    list.reverse!
  end
  private_module_function :fu_split_path

  def fu_relative_components_from(target, base) #:nodoc:
    i = 0
    while target[i]&.== base[i]
      i += 1
    end
    Array.new(base.size-i, '..').concat(target[i..-1])
  end
  private_module_function :fu_relative_components_from

  def fu_clean_components(*comp)
    comp.shift while comp.first == "."
    return comp if comp.empty?
    clean = [comp.shift]
    path = File.join(*clean, "") # ending with File::SEPARATOR
    while c = comp.shift
      if c == ".." and clean.last != ".." and !(fu_have_symlink? && File.symlink?(path))
        clean.pop
        path.chomp!(%r((?<=\A|/)[^/]+/\z), "")
      else
        clean << c
        path << c << "/"
      end
    end
    clean
  end
  private_module_function :fu_clean_components

  if fu_windows?
    def fu_starting_path?(path)
      path&.start_with?(%r(\w:|/))
    end
  else
    def fu_starting_path?(path)
      path&.start_with?("/")
    end
  end
  private_module_function :fu_starting_path?

  # This hash table holds command options.
  OPT_TABLE = {}    #:nodoc: internal use only
  (private_instance_methods & methods(false)).inject(OPT_TABLE) {|tbl, name|
    (tbl[name.to_s] = instance_method(name).parameters).map! {|t, n| n if t == :key}.compact!
    tbl
  }

  public

  # Returns an array of the string names of \FileUtils methods
  # that accept one or more keyword arguments:
  #
  #   FileUtils.commands.sort.take(3) # => ["cd", "chdir", "chmod"]
  #
  def self.commands
    OPT_TABLE.keys
  end

  # Returns an array of the string keyword names:
  #
  #   FileUtils.options.take(3) # => ["noop", "verbose", "force"]
  #
  def self.options
    OPT_TABLE.values.flatten.uniq.map {|sym| sym.to_s }
  end

  # Returns +true+ if method +mid+ accepts the given option +opt+, +false+ otherwise;
  # the arguments may be strings or symbols:
  #
  #   FileUtils.have_option?(:chmod, :noop) # => true
  #   FileUtils.have_option?('chmod', 'secure') # => false
  #
  def self.have_option?(mid, opt)
    li = OPT_TABLE[mid.to_s] or raise ArgumentError, "no such method: #{mid}"
    li.include?(opt)
  end

  # Returns an array of the string keyword name for method +mid+;
  # the argument may be a string or a symbol:
  #
  #   FileUtils.options_of(:rm) # => ["force", "noop", "verbose"]
  #   FileUtils.options_of('mv') # => ["force", "noop", "verbose", "secure"]
  #
  def self.options_of(mid)
    OPT_TABLE[mid.to_s].map {|sym| sym.to_s }
  end

  # Returns an array of the string method names of the methods
  # that accept the given keyword option +opt+;
  # the argument must be a symbol:
  #
  #   FileUtils.collect_method(:preserve) # => ["cp", "copy", "cp_r", "install"]
  #
  def self.collect_method(opt)
    OPT_TABLE.keys.select {|m| OPT_TABLE[m].include?(opt) }
  end

  private

  LOW_METHODS = singleton_methods(false) - collect_method(:noop).map(&:intern) # :nodoc:
  module LowMethods # :nodoc: internal use only
    private
    def _do_nothing(*)end
    ::FileUtils::LOW_METHODS.map {|name| alias_method name, :_do_nothing}
  end

  METHODS = singleton_methods() - [:private_module_function,                  # :nodoc:
      :commands, :options, :have_option?, :options_of, :collect_method]

  #
  # This module has all methods of FileUtils module, but it outputs messages
  # before acting.  This equates to passing the <tt>:verbose</tt> flag to
  # methods in FileUtils.
  #
  module Verbose
    include FileUtils
    names = ::FileUtils.collect_method(:verbose)
    names.each do |name|
      module_eval(<<-EOS, __FILE__, __LINE__ + 1)
        def #{name}(*args, **options)
          super(*args, **options, verbose: true)
        end
      EOS
    end
    private(*names)
    extend self
    class << self
      public(*::FileUtils::METHODS)
    end
  end

  #
  # This module has all methods of FileUtils module, but never changes
  # files/directories.  This equates to passing the <tt>:noop</tt> flag
  # to methods in FileUtils.
  #
  module NoWrite
    include FileUtils
    include LowMethods
    names = ::FileUtils.collect_method(:noop)
    names.each do |name|
      module_eval(<<-EOS, __FILE__, __LINE__ + 1)
        def #{name}(*args, **options)
          super(*args, **options, noop: true)
        end
      EOS
    end
    private(*names)
    extend self
    class << self
      public(*::FileUtils::METHODS)
    end
  end

  #
  # This module has all methods of FileUtils module, but never changes
  # files/directories, with printing message before acting.
  # This equates to passing the <tt>:noop</tt> and <tt>:verbose</tt> flag
  # to methods in FileUtils.
  #
  module DryRun
    include FileUtils
    include LowMethods
    names = ::FileUtils.collect_method(:noop)
    names.each do |name|
      module_eval(<<-EOS, __FILE__, __LINE__ + 1)
        def #{name}(*args, **options)
          super(*args, **options, noop: true, verbose: true)
        end
      EOS
    end
    private(*names)
    extend self
    class << self
      public(*::FileUtils::METHODS)
    end
  end

end
