# frozen_string_literal: true
#
# tmpdir - retrieve temporary directory path
#
# $Id$
#

require 'fileutils'
begin
  require 'etc.so'
rescue LoadError # rescue LoadError for miniruby
end

class Dir

  # Class variables are inaccessible from non-main Ractor.
  # And instance variables too, in Ruby 3.0.

  # System-wide temporary directory path
  SYSTMPDIR = (defined?(Etc.systmpdir) ? Etc.systmpdir.freeze : '/tmp')
  private_constant :SYSTMPDIR

  ##
  # Returns the operating system's temporary file path.

  def self.tmpdir
    ['TMPDIR', 'TMP', 'TEMP', ['system temporary path', SYSTMPDIR], ['/tmp']*2, ['.']*2].find do |name, dir|
      unless dir
        next if !(dir = ENV[name] rescue next) or dir.empty?
      end
      dir = File.expand_path(dir)
      stat = File.stat(dir) rescue next
      case
      when !stat.directory?
        warn "#{name} is not a directory: #{dir}"
      when !stat.writable?
        warn "#{name} is not writable: #{dir}"
      when stat.world_writable? && !stat.sticky?
        warn "#{name} is world-writable: #{dir}"
      else
        break dir
      end
    end or raise ArgumentError, "could not find a temporary directory"
  end

  # Dir.mktmpdir creates a temporary directory.
  #
  # The directory is created with 0700 permission.
  # Application should not change the permission to make the temporary directory accessible from other users.
  #
  # The prefix and suffix of the name of the directory is specified by
  # the optional first argument, <i>prefix_suffix</i>.
  # - If it is not specified or nil, "d" is used as the prefix and no suffix is used.
  # - If it is a string, it is used as the prefix and no suffix is used.
  # - If it is an array, first element is used as the prefix and second element is used as a suffix.
  #
  #  Dir.mktmpdir {|dir| dir is ".../d..." }
  #  Dir.mktmpdir("foo") {|dir| dir is ".../foo..." }
  #  Dir.mktmpdir(["foo", "bar"]) {|dir| dir is ".../foo...bar" }
  #
  # The directory is created under Dir.tmpdir or
  # the optional second argument <i>tmpdir</i> if non-nil value is given.
  #
  #  Dir.mktmpdir {|dir| dir is "#{Dir.tmpdir}/d..." }
  #  Dir.mktmpdir(nil, "/var/tmp") {|dir| dir is "/var/tmp/d..." }
  #
  # If a block is given,
  # it is yielded with the path of the directory.
  # The directory and its contents are removed
  # using FileUtils.remove_entry before Dir.mktmpdir returns.
  # The value of the block is returned.
  #
  #  Dir.mktmpdir {|dir|
  #    # use the directory...
  #    open("#{dir}/foo", "w") { something using the file }
  #  }
  #
  # If a block is not given,
  # The path of the directory is returned.
  # In this case, Dir.mktmpdir doesn't remove the directory.
  #
  #  dir = Dir.mktmpdir
  #  begin
  #    # use the directory...
  #    open("#{dir}/foo", "w") { something using the file }
  #  ensure
  #    # remove the directory.
  #    FileUtils.remove_entry dir
  #  end
  #
  def self.mktmpdir(prefix_suffix=nil, *rest, **options)
    base = nil
    path = Tmpname.create(prefix_suffix || "d", *rest, **options) {|path, _, _, d|
      base = d
      mkdir(path, 0700)
    }
    if block_given?
      begin
        yield path.dup
      ensure
        unless base
          stat = File.stat(File.dirname(path))
          if stat.world_writable? and !stat.sticky?
            raise ArgumentError, "parent directory is world writable but not sticky"
          end
        end
        FileUtils.remove_entry path
      end
    else
      path
    end
  end

  # Temporary name generator
  module Tmpname # :nodoc:
    module_function

    def tmpdir
      Dir.tmpdir
    end

    # Unusable characters as path name
    UNUSABLE_CHARS = "^,-.0-9A-Z_a-z~"

    # Dedicated random number generator
    RANDOM = Object.new
    class << RANDOM # :nodoc:
      # Maximum random number
      MAX = 36**6 # < 0x100000000

      # Returns new random string upto 6 bytes
      def next
        (::Random.urandom(4).unpack1("L")%MAX).to_s(36)
      end
    end
    RANDOM.freeze
    private_constant :RANDOM

    # Generates and yields random names to create a temporary name
    def create(basename, tmpdir=nil, max_try: nil, **opts)
      origdir = tmpdir
      tmpdir ||= tmpdir()
      n = nil
      prefix, suffix = basename
      prefix = (String.try_convert(prefix) or
                raise ArgumentError, "unexpected prefix: #{prefix.inspect}")
      prefix = prefix.delete(UNUSABLE_CHARS)
      suffix &&= (String.try_convert(suffix) or
                  raise ArgumentError, "unexpected suffix: #{suffix.inspect}")
      suffix &&= suffix.delete(UNUSABLE_CHARS)
      begin
        t = Time.now.strftime("%Y%m%d")
        path = "#{prefix}#{t}-#{$$}-#{RANDOM.next}"\
               "#{n ? %[-#{n}] : ''}#{suffix||''}"
        path = File.join(tmpdir, path)
        yield(path, n, opts, origdir)
      rescue Errno::EEXIST
        n ||= 0
        n += 1
        retry if !max_try or n < max_try
        raise "cannot generate temporary name using `#{basename}' under `#{tmpdir}'"
      end
      path
    end
  end
end
