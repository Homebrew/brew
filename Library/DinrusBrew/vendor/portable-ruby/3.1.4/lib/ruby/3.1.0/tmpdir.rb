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

  @@systmpdir ||= defined?(Etc.systmpdir) ? Etc.systmpdir : '/tmp'

  ##
  # Returns the operating system's temporary file path.

  def self.tmpdir
    tmp = nil
    ['TMPDIR', 'TMP', 'TEMP', ['system temporary path', @@systmpdir], ['/tmp']*2, ['.']*2].each do |name, dir = ENV[name]|
      next if !dir
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
        tmp = dir
        break
      end
    end
    raise ArgumentError, "could not find a temporary directory" unless tmp
    tmp
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

  module Tmpname # :nodoc:
    module_function

    def tmpdir
      Dir.tmpdir
    end

    UNUSABLE_CHARS = "^,-.0-9A-Z_a-z~"

    class << (RANDOM = Random.new)
      MAX = 36**6 # < 0x100000000
      def next
        rand(MAX).to_s(36)
      end
    end
    private_constant :RANDOM

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
