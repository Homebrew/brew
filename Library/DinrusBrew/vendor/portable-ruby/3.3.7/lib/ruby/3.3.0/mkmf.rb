# -*- coding: us-ascii -*-
# frozen-string-literal: false
# module to create Makefile for extension modules
# invoke like: ruby -r mkmf extconf.rb

require 'rbconfig'
require 'fileutils'
require 'shellwords'

class String # :nodoc:
  # Wraps a string in escaped quotes if it contains whitespace.
  def quote
    /\s/ =~ self ? "\"#{self}\"" : "#{self}"
  end

  # Escape whitespaces for Makefile.
  def unspace
    gsub(/\s/, '\\\\\\&')
  end

  # Generates a string used as cpp macro name.
  def tr_cpp
    strip.upcase.tr_s("^A-Z0-9_*", "_").tr_s("*", "P")
  end

  def funcall_style
    /\)\z/ =~ self ? dup : "#{self}()"
  end

  def sans_arguments
    self[/\A[^()]+/]
  end
end

class Array # :nodoc:
  # Wraps all strings in escaped quotes if they contain whitespace.
  def quote
    map {|s| s.quote}
  end
end

##
# mkmf.rb is used by Ruby C extensions to generate a Makefile which will
# correctly compile and link the C extension to Ruby and a third-party
# library.
module MakeMakefile
  #### defer until this module become global-state free.
  # def self.extended(obj)
  #   obj.init_mkmf
  #   super
  # end
  #
  # def initialize(*args, rbconfig: RbConfig, **rest)
  #   init_mkmf(rbconfig::MAKEFILE_CONFIG, rbconfig::CONFIG)
  #   super(*args, **rest)
  # end

  ##
  # The makefile configuration using the defaults from when Ruby was built.

  CONFIG = RbConfig::MAKEFILE_CONFIG
  ORIG_LIBPATH = ENV['LIB']

  ##
  # Extensions for files compiled with a C compiler

  C_EXT = %w[c m]

  ##
  # Extensions for files compiled with a C++ compiler

  CXX_EXT = %w[cc mm cxx cpp]
  unless File.exist?(File.join(*File.split(__FILE__).tap {|d, b| b.swapcase}))
    CXX_EXT.concat(%w[C])
  end

  ##
  # Extensions for source files

  SRC_EXT = C_EXT + CXX_EXT

  ##
  # Extensions for header files

  HDR_EXT = %w[h hpp]
  $static = nil
  $config_h = '$(arch_hdrdir)/ruby/config.h'
  $default_static = $static

  unless defined? $configure_args
    $configure_args = {}
    args = CONFIG["configure_args"].shellsplit
    if arg = ENV["CONFIGURE_ARGS"]
      args.push(*arg.shellsplit)
    end
    args.delete_if {|a| /\A--(?:top(?:src)?|src|cur)dir(?=\z|=)/ =~ a}
    for arg in args.concat(ARGV)
      arg, val = arg.split('=', 2)
      next unless arg
      arg.tr!('_', '-')
      if arg.sub!(/\A(?!--)/, '--')
        val or next
        arg.downcase!
      end
      $configure_args[arg] = val || true
    end
  end

  $libdir = CONFIG["libdir"]
  $rubylibdir = CONFIG["rubylibdir"]
  $archdir = CONFIG["archdir"]
  $sitedir = CONFIG["sitedir"]
  $sitelibdir = CONFIG["sitelibdir"]
  $sitearchdir = CONFIG["sitearchdir"]
  $vendordir = CONFIG["vendordir"]
  $vendorlibdir = CONFIG["vendorlibdir"]
  $vendorarchdir = CONFIG["vendorarchdir"]

  $mswin = /mswin/ =~ RUBY_PLATFORM
  $mingw = /mingw/ =~ RUBY_PLATFORM
  $cygwin = /cygwin/ =~ RUBY_PLATFORM
  $netbsd = /netbsd/ =~ RUBY_PLATFORM
  $haiku = /haiku/ =~ RUBY_PLATFORM
  $solaris = /solaris/ =~ RUBY_PLATFORM
  $universal = /universal/ =~ RUBY_PLATFORM
  $dest_prefix_pattern = (File::PATH_SEPARATOR == ';' ? /\A([[:alpha:]]:)?/ : /\A/)

  # :stopdoc:

  def config_string(key, config = CONFIG)
    s = config[key] and !s.empty? and block_given? ? yield(s) : s
  end
  module_function :config_string

  def dir_re(dir)
    Regexp.new('\$(?:\('+dir+'\)|\{'+dir+'\})(?:\$(?:\(target_prefix\)|\{target_prefix\}))?')
  end
  module_function :dir_re

  def relative_from(path, base)
    dir = File.join(path, "")
    if File.expand_path(dir) == File.expand_path(dir, base)
      path
    else
      File.join(base, path)
    end
  end

  INSTALL_DIRS = [
    [dir_re('commondir'), "$(RUBYCOMMONDIR)"],
    [dir_re('sitedir'), "$(RUBYCOMMONDIR)"],
    [dir_re('vendordir'), "$(RUBYCOMMONDIR)"],
    [dir_re('rubylibdir'), "$(RUBYLIBDIR)"],
    [dir_re('archdir'), "$(RUBYARCHDIR)"],
    [dir_re('sitelibdir'), "$(RUBYLIBDIR)"],
    [dir_re('vendorlibdir'), "$(RUBYLIBDIR)"],
    [dir_re('sitearchdir'), "$(RUBYARCHDIR)"],
    [dir_re('vendorarchdir'), "$(RUBYARCHDIR)"],
    [dir_re('rubyhdrdir'), "$(RUBYHDRDIR)"],
    [dir_re('sitehdrdir'), "$(SITEHDRDIR)"],
    [dir_re('vendorhdrdir'), "$(VENDORHDRDIR)"],
    [dir_re('bindir'), "$(BINDIR)"],
  ]

  def install_dirs(target_prefix = nil)
    if $extout and $extmk
      dirs = [
        ['BINDIR',        '$(extout)/bin'],
        ['RUBYCOMMONDIR', '$(extout)/common'],
        ['RUBYLIBDIR',    '$(RUBYCOMMONDIR)$(target_prefix)'],
        ['RUBYARCHDIR',   '$(extout)/$(arch)$(target_prefix)'],
        ['HDRDIR',        '$(extout)/include/ruby$(target_prefix)'],
        ['ARCHHDRDIR',    '$(extout)/include/$(arch)/ruby$(target_prefix)'],
        ['extout',        "#$extout"],
        ['extout_prefix', "#$extout_prefix"],
      ]
    elsif $extmk
      dirs = [
        ['BINDIR',        '$(bindir)'],
        ['RUBYCOMMONDIR', '$(rubylibdir)'],
        ['RUBYLIBDIR',    '$(rubylibdir)$(target_prefix)'],
        ['RUBYARCHDIR',   '$(archdir)$(target_prefix)'],
        ['HDRDIR',        '$(rubyhdrdir)/ruby$(target_prefix)'],
        ['ARCHHDRDIR',    '$(rubyhdrdir)/$(arch)/ruby$(target_prefix)'],
      ]
    elsif $configure_args.has_key?('--vendor')
      dirs = [
        ['BINDIR',        '$(bindir)'],
        ['RUBYCOMMONDIR', '$(vendordir)$(target_prefix)'],
        ['RUBYLIBDIR',    '$(vendorlibdir)$(target_prefix)'],
        ['RUBYARCHDIR',   '$(vendorarchdir)$(target_prefix)'],
        ['HDRDIR',        '$(vendorhdrdir)$(target_prefix)'],
        ['ARCHHDRDIR',    '$(vendorarchhdrdir)$(target_prefix)'],
      ]
    else
      dirs = [
        ['BINDIR',        '$(bindir)'],
        ['RUBYCOMMONDIR', '$(sitedir)$(target_prefix)'],
        ['RUBYLIBDIR',    '$(sitelibdir)$(target_prefix)'],
        ['RUBYARCHDIR',   '$(sitearchdir)$(target_prefix)'],
        ['HDRDIR',        '$(sitehdrdir)$(target_prefix)'],
        ['ARCHHDRDIR',    '$(sitearchhdrdir)$(target_prefix)'],
      ]
    end
    dirs << ['target_prefix', (target_prefix ? "/#{target_prefix}" : "")]
    dirs
  end

  def map_dir(dir, map = nil)
    map ||= INSTALL_DIRS
    map.inject(dir) {|d, (orig, new)| d.gsub(orig, new)}
  end

  topdir = File.dirname(File.dirname(__FILE__))
  path = File.expand_path($0)
  until (dir = File.dirname(path)) == path
    if File.identical?(dir, topdir)
      $extmk = true if %r"\A(?:ext|enc|tool|test)\z" =~ File.basename(path)
      break
    end
    path = dir
  end
  $extmk ||= false
  if not $extmk and File.exist?(($hdrdir = RbConfig::CONFIG["rubyhdrdir"]) + "/ruby/ruby.h")
    $topdir = $hdrdir
    $top_srcdir = $hdrdir
    $arch_hdrdir = RbConfig::CONFIG["rubyarchhdrdir"]
  elsif File.exist?(($hdrdir = ($top_srcdir ||= topdir) + "/include")  + "/ruby.h")
    $topdir ||= RbConfig::CONFIG["topdir"]
    $arch_hdrdir = "$(extout)/include/$(arch)"
  else
    abort <<MESSAGE
mkmf.rb can't find header files for ruby at #{$hdrdir}/ruby.h

You might have to install separate package for the ruby development
environment, ruby-dev or ruby-devel for example.
MESSAGE
  end

  CONFTEST = "conftest".freeze
  CONFTEST_C = "#{CONFTEST}.c"

  OUTFLAG = CONFIG['OUTFLAG']
  COUTFLAG = CONFIG['COUTFLAG']
  CSRCFLAG = CONFIG['CSRCFLAG']
  CPPOUTFILE = config_string('CPPOUTFILE') {|str| str.sub(/\bconftest\b/, CONFTEST)}

  def rm_f(*files)
    opt = (Hash === files.last ? [files.pop] : [])
    FileUtils.rm_f(Dir[*files.flatten], *opt)
  end
  module_function :rm_f

  def rm_rf(*files)
    opt = (Hash === files.last ? [files.pop] : [])
    FileUtils.rm_rf(Dir[*files.flatten], *opt)
  end
  module_function :rm_rf

  # Returns time stamp of the +target+ file if it exists and is newer than or
  # equal to all of +times+.
  def modified?(target, times)
    (t = File.mtime(target)) rescue return nil
    Array === times or times = [times]
    t if times.all? {|n| n <= t}
  end

  def split_libs(*strs)
    sep = $mswin ? /\s+/ : /\s+(?=-|\z)/
    strs.flat_map {|s| s.lstrip.split(sep)}
  end

  def merge_libs(*libs)
    libs.inject([]) do |x, y|
      y = y.inject([]) {|ary, e| ary.last == e ? ary : ary << e}
      y.each_with_index do |v, yi|
        if xi = x.rindex(v)
          x[(xi+1)..-1] = merge_libs(y[(yi+1)..-1], x[(xi+1)..-1])
          x[xi, 0] = y[0...yi]
          break
        end
      end and x.concat(y)
      x
    end
  end

  # This is a custom logging module. It generates an mkmf.log file when you
  # run your extconf.rb script. This can be useful for debugging unexpected
  # failures.
  #
  # This module and its associated methods are meant for internal use only.
  #
  module Logging
    @log = nil
    @logfile = 'mkmf.log'
    @orgerr = $stderr.dup
    @orgout = $stdout.dup
    @postpone = 0
    @quiet = $extmk

    def self::log_open
      @log ||= File::open(@logfile, 'wb')
      @log.sync = true
    end

    def self::log_opened?
      @log and not @log.closed?
    end

    def self::open
      log_open
      $stderr.reopen(@log)
      $stdout.reopen(@log)
      yield
    ensure
      $stderr.reopen(@orgerr)
      $stdout.reopen(@orgout)
    end

    def self::message(*s)
      log_open
      @log.printf(*s)
    end

    def self::logfile file
      @logfile = file
      log_close
    end

    def self::log_close
      if @log and not @log.closed?
        @log.flush
        @log.close
        @log = nil
      end
    end

    def self::postpone
      tmplog = "mkmftmp#{@postpone += 1}.log"
      open do
        log, *save = @log, @logfile, @orgout, @orgerr
        @log, @logfile, @orgout, @orgerr = nil, tmplog, log, log
        begin
          log.print(open {yield @log})
        ensure
          @log.close if @log and not @log.closed?
          File::open(tmplog) {|t| FileUtils.copy_stream(t, log)} if File.exist?(tmplog)
          @log, @logfile, @orgout, @orgerr = log, *save
          @postpone -= 1
          MakeMakefile.rm_f tmplog
        end
      end
    end

    class << self
      attr_accessor :quiet
    end
  end

  def libpath_env
    # used only if native compiling
    if libpathenv = config_string("LIBPATHENV")
      pathenv = ENV[libpathenv]
      libpath = RbConfig.expand($DEFLIBPATH.join(File::PATH_SEPARATOR))
      {libpathenv => [libpath, pathenv].compact.join(File::PATH_SEPARATOR)}
    else
      {}
    end
  end

  def expand_command(commands, envs = libpath_env)
    varpat = /\$\((\w+)\)|\$\{(\w+)\}/
    vars = nil
    expand = proc do |command|
      case command
      when Array
        command.map(&expand)
      when String
        if varpat =~ command
          vars ||= Hash.new {|h, k| h[k] = ENV[k]}
          command = command.dup
          nil while command.gsub!(varpat) {vars[$1||$2]}
        end
        command
      else
        command
      end
    end
    if Array === commands
      env, *commands = commands if Hash === commands.first
      envs.merge!(env) if env
    end
    return envs, expand[commands]
  end

  def env_quote(envs)
    envs.map {|e, v| "#{e}=#{v.quote}"}
  end

  def xsystem command, opts = nil
    env, command = expand_command(command)
    Logging::open do
      puts [env_quote(env), command.quote].join(' ')
      if opts and opts[:werror]
        result = nil
        Logging.postpone do |log|
          output = IO.popen(env, command, &:read)
          result = ($?.success? and File.zero?(log.path))
          output
        end
        result
      else
        system(env, *command)
      end
    end
  end

  def xpopen command, *mode, &block
    env, commands = expand_command(command)
    command = [env_quote(env), command].join(' ')
    Logging::open do
      case mode[0]
      when nil, Hash, /^r/
        puts "#{command} |"
      else
        puts "| #{command}"
      end
      IO.popen(env, commands, *mode, &block)
    end
  end

  def log_src(src, heading="checked program was")
    src = src.split(/^/)
    fmt = "%#{src.size.to_s.size}d: %s"
    Logging::message <<"EOM"
#{heading}:
/* begin */
EOM
    src.each_with_index {|line, no| Logging::message fmt, no+1, line}
    Logging::message <<"EOM"
/* end */

EOM
  end

  def conftest_source
    CONFTEST_C
  end

  def create_tmpsrc(src)
    src = "#{COMMON_HEADERS}\n#{src}"
    src = yield(src) if block_given?
    src.gsub!(/[ \t]+$/, '')
    src.gsub!(/\A\n+|^\n+$/, '')
    src.sub!(/[^\n]\z/, "\\&\n")
    count = 0
    begin
      File.open(conftest_source, "wb") do |cfile|
        cfile.print src
      end
    rescue Errno::EACCES
      if (count += 1) < 5
        sleep 0.2
        retry
      end
    end
    src
  end

  def have_devel?
    unless defined? $have_devel
      $have_devel = true
      $have_devel = try_link(MAIN_DOES_NOTHING)
    end
    $have_devel
  end

  def try_do(src, command, *opts, &b)
    unless have_devel?
      raise <<MSG
The compiler failed to generate an executable file.
You have to install development tools first.
MSG
    end
    begin
      src = create_tmpsrc(src, &b)
      xsystem(command, *opts)
    ensure
      log_src(src)
    end
  end

  def link_config(ldflags, opt="", libpath=$DEFLIBPATH|$LIBPATH)
    librubyarg = $extmk ? $LIBRUBYARG_STATIC : "$(LIBRUBYARG)"
    conf = RbConfig::CONFIG.merge('hdrdir' => $hdrdir.quote,
                                  'src' => "#{conftest_source}",
                                  'arch_hdrdir' => $arch_hdrdir.quote,
                                  'top_srcdir' => $top_srcdir.quote,
                                  'INCFLAGS' => "#$INCFLAGS",
                                  'CPPFLAGS' => "#$CPPFLAGS",
                                  'CFLAGS' => "#$CFLAGS",
                                  'ARCH_FLAG' => "#$ARCH_FLAG",
                                  'LDFLAGS' => "#$LDFLAGS #{ldflags}",
                                  'LOCAL_LIBS' => "#$LOCAL_LIBS #$libs",
                                  'LIBS' => "#{librubyarg} #{opt} #$LIBS")
    conf['LIBPATH'] = libpathflag(libpath.map {|s| RbConfig::expand(s.dup, conf)})
    conf
  end

  def link_command(ldflags, *opts)
    conf = link_config(ldflags, *opts)
    RbConfig::expand(TRY_LINK.dup, conf)
  end

  def cc_config(opt="")
    conf = RbConfig::CONFIG.merge('hdrdir' => $hdrdir.quote, 'srcdir' => $srcdir.quote,
                                  'arch_hdrdir' => $arch_hdrdir.quote,
                                  'top_srcdir' => $top_srcdir.quote)
    conf
  end

  def cc_command(opt="")
    conf = cc_config(opt)
    RbConfig::expand("$(CC) #$INCFLAGS #$CPPFLAGS #$CFLAGS #$ARCH_FLAG #{opt} -c #{CONFTEST_C}",
                     conf)
  end

  def cpp_command(outfile, opt="")
    conf = cc_config(opt)
    if $universal and (arch_flag = conf['ARCH_FLAG']) and !arch_flag.empty?
      conf['ARCH_FLAG'] = arch_flag.gsub(/(?:\G|\s)-arch\s+\S+/, '')
    end
    RbConfig::expand("$(CPP) #$INCFLAGS #$CPPFLAGS #$CFLAGS #{opt} #{CONFTEST_C} #{outfile}",
                     conf)
  end

  def libpathflag(libpath=$DEFLIBPATH|$LIBPATH)
    libpath.map{|x|
      case x
      when "$(topdir)", /\A\./
        LIBPATHFLAG
      else
        LIBPATHFLAG+RPATHFLAG
      end % x.quote
    }.join
  end

  def with_werror(opt, opts = nil)
    if opts
      if opts[:werror] and config_string("WERRORFLAG") {|flag| opt = opt ? "#{opt} #{flag}" : flag}
        (opts = opts.dup).delete(:werror)
      end
      yield(opt, opts)
    else
      yield(opt)
    end
  end

  def try_link0(src, opt="", *opts, &b) # :nodoc:
    exe = CONFTEST+$EXEEXT
    cmd = link_command("", opt)
    if $universal
      require 'tmpdir'
      Dir.mktmpdir("mkmf_", oldtmpdir = ENV["TMPDIR"]) do |tmpdir|
        begin
          ENV["TMPDIR"] = tmpdir
          try_do(src, cmd, *opts, &b)
        ensure
          ENV["TMPDIR"] = oldtmpdir
        end
      end
    else
      try_do(src, cmd, *opts, &b)
    end and File.executable?(exe) or return nil
    exe
  ensure
    MakeMakefile.rm_rf(*Dir["#{CONFTEST}*"]-[exe])
  end

  # Returns whether or not the +src+ can be compiled as a C source and linked
  # with its depending libraries successfully.  +opt+ is passed to the linker
  # as options. Note that +$CFLAGS+ and +$LDFLAGS+ are also passed to the
  # linker.
  #
  # If a block given, it is called with the source before compilation. You can
  # modify the source in the block.
  #
  # [+src+] a String which contains a C source
  # [+opt+] a String which contains linker options
  def try_link(src, opt="", *opts, &b)
    exe = try_link0(src, opt, *opts, &b) or return false
    MakeMakefile.rm_f exe
    true
  end

  # Returns whether or not the +src+ can be compiled as a C source.  +opt+ is
  # passed to the C compiler as options. Note that +$CFLAGS+ is also passed to
  # the compiler.
  #
  # If a block given, it is called with the source before compilation. You can
  # modify the source in the block.
  #
  # [+src+] a String which contains a C source
  # [+opt+] a String which contains compiler options
  def try_compile(src, opt="", *opts, &b)
    with_werror(opt, *opts) {|_opt, *| try_do(src, cc_command(_opt), *opts, &b)} and
      File.file?("#{CONFTEST}.#{$OBJEXT}")
  ensure
    MakeMakefile.rm_f "#{CONFTEST}*"
  end

  # Returns whether or not the +src+ can be preprocessed with the C
  # preprocessor.  +opt+ is passed to the preprocessor as options. Note that
  # +$CFLAGS+ is also passed to the preprocessor.
  #
  # If a block given, it is called with the source before preprocessing. You
  # can modify the source in the block.
  #
  # [+src+] a String which contains a C source
  # [+opt+] a String which contains preprocessor options
  def try_cpp(src, opt="", *opts, &b)
    try_do(src, cpp_command(CPPOUTFILE, opt), *opts, &b) and
      File.file?("#{CONFTEST}.i")
  ensure
    MakeMakefile.rm_f "#{CONFTEST}*"
  end

  alias try_header try_compile

  def cpp_include(header)
    if header
      header = [header] unless header.kind_of? Array
      header.map {|h| String === h ? "#include <#{h}>\n" : h}.join
    else
      ""
    end
  end

  def with_cppflags(flags)
    cppflags = $CPPFLAGS
    $CPPFLAGS = flags.dup
    ret = yield
  ensure
    $CPPFLAGS = cppflags unless ret
  end

  def try_cppflags(flags, opts = {})
    try_header(MAIN_DOES_NOTHING, flags, {:werror => true}.update(opts))
  end

  def append_cppflags(flags, *opts)
    Array(flags).each do |flag|
      if checking_for("whether #{flag} is accepted as CPPFLAGS") {
           try_cppflags(flag, *opts)
         }
        $CPPFLAGS << " " << flag
      end
    end
  end

  def with_cflags(flags)
    cflags = $CFLAGS
    $CFLAGS = flags.dup
    ret = yield
  ensure
    $CFLAGS = cflags unless ret
  end

  def try_cflags(flags, opts = {})
    try_compile(MAIN_DOES_NOTHING, flags, {:werror => true}.update(opts))
  end

  def with_ldflags(flags)
    ldflags = $LDFLAGS
    $LDFLAGS = flags.dup
    ret = yield
  ensure
    $LDFLAGS = ldflags unless ret
  end

  def try_ldflags(flags, opts = {})
    opts = {:werror => true}.update(opts) if $mswin
    try_link(MAIN_DOES_NOTHING, flags, opts)
  end

  def append_ldflags(flags, *opts)
    Array(flags).each do |flag|
      if checking_for("whether #{flag} is accepted as LDFLAGS") {
           try_ldflags(flag, *opts)
         }
        $LDFLAGS << " " << flag
      end
    end
  end

  def try_static_assert(expr, headers = nil, opt = "", &b)
    headers = cpp_include(headers)
    try_compile(<<SRC, opt, &b)
#{headers}
/*top*/
int conftest_const[(#{expr}) ? 1 : -1];
SRC
  end

  def try_constant(const, headers = nil, opt = "", &b)
    includes = cpp_include(headers)
    neg = try_static_assert("#{const} < 0", headers, opt)
    if CROSS_COMPILING
      if neg
        const = "-(#{const})"
      elsif try_static_assert("#{const} > 0", headers, opt)
        # positive constant
      elsif try_static_assert("#{const} == 0", headers, opt)
        return 0
      else
        # not a constant
        return nil
      end
      upper = 1
      until try_static_assert("#{const} <= #{upper}", headers, opt)
        lower = upper
        upper <<= 1
      end
      return nil unless lower
      while upper > lower + 1
        mid = (upper + lower) / 2
        if try_static_assert("#{const} > #{mid}", headers, opt)
          lower = mid
        else
          upper = mid
        end
      end
      upper = -upper if neg
      return upper
    else
      src = %{#{includes}
#include <stdio.h>
/*top*/
typedef#{neg ? '' : ' unsigned'}
#ifdef PRI_LL_PREFIX
#define PRI_CONFTEST_PREFIX PRI_LL_PREFIX
LONG_LONG
#else
#define PRI_CONFTEST_PREFIX "l"
long
#endif
conftest_type;
conftest_type conftest_const = (conftest_type)(#{const});
int main() {printf("%"PRI_CONFTEST_PREFIX"#{neg ? 'd' : 'u'}\\n", conftest_const); return 0;}
}
      begin
        if try_link0(src, opt, &b)
          xpopen("./#{CONFTEST}") do |f|
            return Integer(f.gets)
          end
        end
      ensure
        MakeMakefile.rm_f "#{CONFTEST}#{$EXEEXT}"
      end
    end
    nil
  end

  # You should use +have_func+ rather than +try_func+.
  #
  # [+func+] a String which contains a symbol name
  # [+libs+] a String which contains library names.
  # [+headers+] a String or an Array of strings which contains names of header
  #             files.
  def try_func(func, libs, headers = nil, opt = "", &b)
    headers = cpp_include(headers)
    prepare = String.new
    case func
    when /^&/
      decltype = proc {|x|"const volatile void *#{x}"}
    when /\)$/
      strvars = []
      call = func.gsub(/""/) {
        v = "s#{strvars.size + 1}"
        strvars << v
        v
      }
      unless strvars.empty?
        prepare << "char " << strvars.map {|v| "#{v}[1024]"}.join(", ") << "; "
      end
    when nil
      call = ""
    else
      call = "#{func}()"
      decltype = proc {|x| "void ((*#{x})())"}
    end
    if opt and !opt.empty?
      [[:to_str], [:join, " "], [:to_s]].each do |meth, *args|
        if opt.respond_to?(meth)
          break opt = opt.__send__(meth, *args)
        end
      end
      opt = "#{opt} #{libs}"
    else
      opt = libs
    end
    decltype && try_link(<<"SRC", opt, &b) or
#{headers}
/*top*/
extern int t(void);
#{MAIN_DOES_NOTHING 't'}
int t(void) { #{decltype["volatile p"]}; p = (#{decltype[]})#{func}; return !p; }
SRC
    call && try_link(<<"SRC", opt, &b)
#{headers}
/*top*/
extern int t(void);
#{MAIN_DOES_NOTHING 't'}
#{"extern void #{call};" if decltype}
int t(void) { #{prepare}#{call}; return 0; }
SRC
  end

  # You should use +have_var+ rather than +try_var+.
  def try_var(var, headers = nil, opt = "", &b)
    headers = cpp_include(headers)
    try_compile(<<"SRC", opt, &b)
#{headers}
/*top*/
extern int t(void);
#{MAIN_DOES_NOTHING 't'}
int t(void) { const volatile void *volatile p; p = &(&#{var})[0]; return !p; }
SRC
  end

  # Returns whether or not the +src+ can be preprocessed with the C
  # preprocessor and matches with +pat+.
  #
  # If a block given, it is called with the source before compilation. You can
  # modify the source in the block.
  #
  # [+pat+] a Regexp or a String
  # [+src+] a String which contains a C source
  # [+opt+] a String which contains preprocessor options
  #
  # NOTE: When pat is a Regexp the matching will be checked in process,
  # otherwise egrep(1) will be invoked to check it.
  def egrep_cpp(pat, src, opt = "", &b)
    src = create_tmpsrc(src, &b)
    xpopen(cpp_command('', opt)) do |f|
      if Regexp === pat
        puts("    ruby -ne 'print if #{pat.inspect}'")
        f.grep(pat) {|l|
          puts "#{f.lineno}: #{l}"
          return true
        }
        false
      else
        puts("    egrep '#{pat}'")
        begin
          stdin = $stdin.dup
          $stdin.reopen(f)
          system("egrep", pat)
        ensure
          $stdin.reopen(stdin)
        end
      end
    end
  ensure
    MakeMakefile.rm_f "#{CONFTEST}*"
    log_src(src)
  end

  # This is used internally by the have_macro? method.
  def macro_defined?(macro, src, opt = "", &b)
    src = src.sub(/[^\n]\z/, "\\&\n")
    try_compile(src + <<"SRC", opt, &b)
/*top*/
#ifndef #{macro}
# error
|:/ === #{macro} undefined === /:|
#endif
SRC
  end

  # Returns whether or not:
  # * the +src+ can be compiled as a C source,
  # * the result object can be linked with its depending libraries
  #   successfully,
  # * the linked file can be invoked as an executable
  # * and the executable exits successfully
  #
  # +opt+ is passed to the linker as options. Note that +$CFLAGS+ and
  # +$LDFLAGS+ are also passed to the linker.
  #
  # If a block given, it is called with the source before compilation. You can
  # modify the source in the block.
  #
  # [+src+] a String which contains a C source
  # [+opt+] a String which contains linker options
  #
  # Returns true when the executable exits successfully, false when it fails,
  # or nil when preprocessing, compilation or link fails.
  def try_run(src, opt = "", &b)
    raise "cannot run test program while cross compiling" if CROSS_COMPILING
    if try_link0(src, opt, &b)
      xsystem("./#{CONFTEST}")
    else
      nil
    end
  ensure
    MakeMakefile.rm_f "#{CONFTEST}*"
  end

  def install_files(mfile, ifiles, map = nil, srcprefix = nil)
    ifiles or return
    ifiles.empty? and return
    srcprefix ||= "$(srcdir)/#{srcprefix}".chomp('/')
    RbConfig::expand(srcdir = srcprefix.dup)
    dirs = []
    path = Hash.new {|h, i| h[i] = dirs.push([i])[-1]}
    ifiles.each do |files, dir, prefix|
      dir = map_dir(dir, map)
      prefix &&= %r|\A#{Regexp.quote(prefix)}/?|
      if /\A\.\// =~ files
        # install files which are in current working directory.
        files = files[2..-1]
        len = nil
      else
        # install files which are under the $(srcdir).
        files = File.join(srcdir, files)
        len = srcdir.size
      end
      f = nil
      Dir.glob(files) do |fx|
        f = fx
        f[0..len] = "" if len
        case File.basename(f)
        when *$NONINSTALLFILES
          next
        end
        d = File.dirname(f)
        d.sub!(prefix, "") if prefix
        d = (d.empty? || d == ".") ? dir : File.join(dir, d)
        f = File.join(srcprefix, f) if len
        path[d] << f
      end
      unless len or f
        d = File.dirname(files)
        d.sub!(prefix, "") if prefix
        d = (d.empty? || d == ".") ? dir : File.join(dir, d)
        path[d] << files
      end
    end
    dirs
  end

  def install_rb(mfile, dest, srcdir = nil)
    install_files(mfile, [["lib/**/*.rb", dest, "lib"]], nil, srcdir)
  end

  def append_library(libs, lib) # :no-doc:
    format(LIBARG, lib) + " " + libs
  end

  def message(*s)
    unless Logging.quiet and not $VERBOSE
      printf(*s)
      $stdout.flush
    end
  end

  # This emits a string to stdout that allows users to see the results of the
  # various have* and find* methods as they are tested.
  #
  # Internal use only.
  #
  def checking_for(m, fmt = nil)
    if f = caller_locations(1, 1).first.base_label and /\A\w/ =~ f
      f += ": "
    else
      f = ""
    end
    m = "checking #{/\Acheck/ =~ f ? '' : 'for '}#{m}... "
    message "%s", m
    a = r = nil
    Logging::postpone do
      r = yield
      a = (fmt ? "#{fmt % r}" : r ? "yes" : "no")
      "#{f}#{m}-------------------- #{a}\n\n"
    end
    message "%s\n", a
    Logging::message "--------------------\n\n"
    r
  end

  def checking_message(target, place = nil, opt = nil)
    [["in", place], ["with", opt]].inject("#{target}") do |msg, (pre, noun)|
      if noun
        [[:to_str], [:join, ","], [:to_s]].each do |meth, *args|
          if noun.respond_to?(meth)
            break noun = noun.__send__(meth, *args)
          end
        end
        unless noun.empty?
          msg << " #{pre} " unless msg.empty?
          msg << noun
        end
      end
      msg
    end
  end

  # :startdoc:

  # Check whether each given C compiler flag is acceptable and append it
  # to <tt>$CFLAGS</tt> if so.
  #
  # [+flags+] a C compiler flag as a +String+ or an +Array+ of them
  #
  def append_cflags(flags, *opts)
    Array(flags).each do |flag|
      if checking_for("whether #{flag} is accepted as CFLAGS") {
           try_cflags(flag, *opts)
         }
        $CFLAGS << " " << flag
      end
    end
  end

  # Returns whether or not +macro+ is defined either in the common header
  # files or within any +headers+ you provide.
  #
  # Any options you pass to +opt+ are passed along to the compiler.
  #
  def have_macro(macro, headers = nil, opt = "", &b)
    checking_for checking_message(macro, headers, opt) do
      macro_defined?(macro, cpp_include(headers), opt, &b)
    end
  end

  # Returns whether or not the given entry point +func+ can be found within
  # +lib+.  If +func+ is +nil+, the <code>main()</code> entry point is used by
  # default.  If found, it adds the library to list of libraries to be used
  # when linking your extension.
  #
  # If +headers+ are provided, it will include those header files as the
  # header files it looks in when searching for +func+.
  #
  # The real name of the library to be linked can be altered by
  # <code>--with-FOOlib</code> configuration option.
  #
  def have_library(lib, func = nil, headers = nil, opt = "", &b)
    dir_config(lib)
    lib = with_config(lib+'lib', lib)
    checking_for checking_message(func && func.funcall_style, LIBARG%lib, opt) do
      if COMMON_LIBS.include?(lib)
        true
      else
        libs = append_library($libs, lib)
        if try_func(func, libs, headers, opt, &b)
          $libs = libs
          true
        else
          false
        end
      end
    end
  end

  # Returns whether or not the entry point +func+ can be found within the
  # library +lib+ in one of the +paths+ specified, where +paths+ is an array
  # of strings.  If +func+ is +nil+ , then the <code>main()</code> function is
  # used as the entry point.
  #
  # If +lib+ is found, then the path it was found on is added to the list of
  # library paths searched and linked against.
  #
  def find_library(lib, func, *paths, &b)
    dir_config(lib)
    lib = with_config(lib+'lib', lib)
    paths = paths.flat_map {|path| path.split(File::PATH_SEPARATOR)}
    checking_for checking_message(func && func.funcall_style, LIBARG%lib) do
      libpath = $LIBPATH
      libs = append_library($libs, lib)
      begin
        until r = try_func(func, libs, &b) or paths.empty?
          $LIBPATH = libpath | [paths.shift]
        end
        if r
          $libs = libs
          libpath = nil
        end
      ensure
        $LIBPATH = libpath if libpath
      end
      r
    end
  end

  # Returns whether or not the function +func+ can be found in the common
  # header files, or within any +headers+ that you provide.  If found, a macro
  # is passed as a preprocessor constant to the compiler using the function
  # name, in uppercase, prepended with +HAVE_+.
  #
  # To check functions in an additional library, you need to check that
  # library first using <code>have_library()</code>.  The +func+ shall be
  # either mere function name or function name with arguments.
  #
  # For example, if <code>have_func('foo')</code> returned +true+, then the
  # +HAVE_FOO+ preprocessor macro would be passed to the compiler.
  #
  def have_func(func, headers = nil, opt = "", &b)
    checking_for checking_message(func.funcall_style, headers, opt) do
      if try_func(func, $libs, headers, opt, &b)
        $defs << "-DHAVE_#{func.sans_arguments.tr_cpp}"
        true
      else
        false
      end
    end
  end

  # Returns whether or not the variable +var+ can be found in the common
  # header files, or within any +headers+ that you provide.  If found, a macro
  # is passed as a preprocessor constant to the compiler using the variable
  # name, in uppercase, prepended with +HAVE_+.
  #
  # To check variables in an additional library, you need to check that
  # library first using <code>have_library()</code>.
  #
  # For example, if <code>have_var('foo')</code> returned true, then the
  # +HAVE_FOO+ preprocessor macro would be passed to the compiler.
  #
  def have_var(var, headers = nil, opt = "", &b)
    checking_for checking_message(var, headers, opt) do
      if try_var(var, headers, opt, &b)
        $defs.push(format("-DHAVE_%s", var.tr_cpp))
        true
      else
        false
      end
    end
  end

  # Returns whether or not the given +header+ file can be found on your system.
  # If found, a macro is passed as a preprocessor constant to the compiler
  # using the header file name, in uppercase, prepended with +HAVE_+.
  #
  # For example, if <code>have_header('foo.h')</code> returned true, then the
  # +HAVE_FOO_H+ preprocessor macro would be passed to the compiler.
  #
  def have_header(header, preheaders = nil, opt = "", &b)
    dir_config(header[/.*?(?=\/)|.*?(?=\.)/])
    checking_for header do
      if try_header(cpp_include(preheaders)+cpp_include(header), opt, &b)
        $defs.push(format("-DHAVE_%s", header.tr_cpp))
        true
      else
        false
      end
    end
  end

  # Returns whether or not the given +framework+ can be found on your system.
  # If found, a macro is passed as a preprocessor constant to the compiler
  # using the framework name, in uppercase, prepended with +HAVE_FRAMEWORK_+.
  #
  # For example, if <code>have_framework('Ruby')</code> returned true, then
  # the +HAVE_FRAMEWORK_RUBY+ preprocessor macro would be passed to the
  # compiler.
  #
  # If +fw+ is a pair of the framework name and its header file name
  # that header file is checked, instead of the normally used header
  # file which is named same as the framework.
  def have_framework(fw, &b)
    if Array === fw
      fw, header = *fw
    else
      header = "#{fw}.h"
    end
    checking_for fw do
      src = cpp_include("#{fw}/#{header}") << "\n" "int main(void){return 0;}"
      opt = " -framework #{fw}"
      if try_link(src, opt, &b) or (objc = try_link(src, "-ObjC#{opt}", &b))
        $defs.push(format("-DHAVE_FRAMEWORK_%s", fw.tr_cpp))
        # TODO: non-worse way than this hack, to get rid of separating
        # option and its argument.
        $LDFLAGS << " -ObjC" if objc and /(\A|\s)-ObjC(\s|\z)/ !~ $LDFLAGS
        $LIBS << opt
        true
      else
        false
      end
    end
  end

  # Instructs mkmf to search for the given +header+ in any of the +paths+
  # provided, and returns whether or not it was found in those paths.
  #
  # If the header is found then the path it was found on is added to the list
  # of included directories that are sent to the compiler (via the
  # <code>-I</code> switch).
  #
  def find_header(header, *paths)
    message = checking_message(header, paths)
    header = cpp_include(header)
    checking_for message do
      if try_header(header)
        true
      else
        found = false
        paths.each do |dir|
          opt = "-I#{dir}".quote
          if try_header(header, opt)
            $INCFLAGS << " " << opt
            found = true
            break
          end
        end
        found
      end
    end
  end

  # Returns whether or not the struct of type +type+ contains +member+.  If
  # it does not, or the struct type can't be found, then false is returned.
  # You may optionally specify additional +headers+ in which to look for the
  # struct (in addition to the common header files).
  #
  # If found, a macro is passed as a preprocessor constant to the compiler
  # using the type name and the member name, in uppercase, prepended with
  # +HAVE_+.
  #
  # For example, if <code>have_struct_member('struct foo', 'bar')</code>
  # returned true, then the +HAVE_STRUCT_FOO_BAR+ preprocessor macro would be
  # passed to the compiler.
  #
  # +HAVE_ST_BAR+ is also defined for backward compatibility.
  #
  def have_struct_member(type, member, headers = nil, opt = "", &b)
    checking_for checking_message("#{type}.#{member}", headers) do
      if try_compile(<<"SRC", opt, &b)
#{cpp_include(headers)}
/*top*/
int s = (char *)&((#{type}*)0)->#{member} - (char *)0;
#{MAIN_DOES_NOTHING}
SRC
        $defs.push(format("-DHAVE_%s_%s", type.tr_cpp, member.tr_cpp))
        $defs.push(format("-DHAVE_ST_%s", member.tr_cpp)) # backward compatibility
        true
      else
        false
      end
    end
  end

  # Returns whether or not the static type +type+ is defined.
  #
  # See also +have_type+
  #
  def try_type(type, headers = nil, opt = "", &b)
    if try_compile(<<"SRC", opt, &b)
#{cpp_include(headers)}
/*top*/
typedef #{type} conftest_type;
int conftestval[sizeof(conftest_type)?1:-1];
SRC
      $defs.push(format("-DHAVE_TYPE_%s", type.tr_cpp))
      true
    else
      false
    end
  end

  # Returns whether or not the static type +type+ is defined.  You may
  # optionally pass additional +headers+ to check against in addition to the
  # common header files.
  #
  # You may also pass additional flags to +opt+ which are then passed along to
  # the compiler.
  #
  # If found, a macro is passed as a preprocessor constant to the compiler
  # using the type name, in uppercase, prepended with +HAVE_TYPE_+.
  #
  # For example, if <code>have_type('foo')</code> returned true, then the
  # +HAVE_TYPE_FOO+ preprocessor macro would be passed to the compiler.
  #
  def have_type(type, headers = nil, opt = "", &b)
    checking_for checking_message(type, headers, opt) do
      try_type(type, headers, opt, &b)
    end
  end

  # Returns where the static type +type+ is defined.
  #
  # You may also pass additional flags to +opt+ which are then passed along to
  # the compiler.
  #
  # See also +have_type+.
  #
  def find_type(type, opt, *headers, &b)
    opt ||= ""
    fmt = "not found"
    def fmt.%(x)
      x ? x.respond_to?(:join) ? x.join(",") : x : self
    end
    checking_for checking_message(type, nil, opt), fmt do
      headers.find do |h|
        try_type(type, h, opt, &b)
      end
    end
  end

  # Returns whether or not the constant +const+ is defined.
  #
  # See also +have_const+
  #
  def try_const(const, headers = nil, opt = "", &b)
    const, type = *const
    if try_compile(<<"SRC", opt, &b)
#{cpp_include(headers)}
/*top*/
typedef #{type || 'int'} conftest_type;
conftest_type conftestval = #{type ? '' : '(int)'}#{const};
SRC
      $defs.push(format("-DHAVE_CONST_%s", const.tr_cpp))
      true
    else
      false
    end
  end

  # Returns whether or not the constant +const+ is defined.  You may
  # optionally pass the +type+ of +const+ as <code>[const, type]</code>,
  # such as:
  #
  #   have_const(%w[PTHREAD_MUTEX_INITIALIZER pthread_mutex_t], "pthread.h")
  #
  # You may also pass additional +headers+ to check against in addition to the
  # common header files, and additional flags to +opt+ which are then passed
  # along to the compiler.
  #
  # If found, a macro is passed as a preprocessor constant to the compiler
  # using the type name, in uppercase, prepended with +HAVE_CONST_+.
  #
  # For example, if <code>have_const('foo')</code> returned true, then the
  # +HAVE_CONST_FOO+ preprocessor macro would be passed to the compiler.
  #
  def have_const(const, headers = nil, opt = "", &b)
    checking_for checking_message([*const].compact.join(' '), headers, opt) do
      try_const(const, headers, opt, &b)
    end
  end

  # :stopdoc:
  STRING_OR_FAILED_FORMAT = "%s"
  class << STRING_OR_FAILED_FORMAT # :nodoc:
    def %(x)
      x ? super : "failed"
    end
  end

  def typedef_expr(type, headers)
    typename, member = type.split('.', 2)
    prelude = cpp_include(headers).split(/$/)
    prelude << "typedef #{typename} rbcv_typedef_;\n"
    return "rbcv_typedef_", member, prelude
  end

  def try_signedness(type, member, headers = nil, opts = nil)
    raise ArgumentError, "don't know how to tell signedness of members" if member
    if try_static_assert("(#{type})-1 < 0", headers, opts)
      return -1
    elsif try_static_assert("(#{type})-1 > 0", headers, opts)
      return +1
    end
  end

  # :startdoc:

  # Returns the size of the given +type+.  You may optionally specify
  # additional +headers+ to search in for the +type+.
  #
  # If found, a macro is passed as a preprocessor constant to the compiler
  # using the type name, in uppercase, prepended with +SIZEOF_+, followed by
  # the type name, followed by <code>=X</code> where "X" is the actual size.
  #
  # For example, if <code>check_sizeof('mystruct')</code> returned 12, then
  # the <code>SIZEOF_MYSTRUCT=12</code> preprocessor macro would be passed to
  # the compiler.
  #
  def check_sizeof(type, headers = nil, opts = "", &b)
    typedef, member, prelude = typedef_expr(type, headers)
    prelude << "#{typedef} *rbcv_ptr_;\n"
    prelude = [prelude]
    expr = "sizeof((*rbcv_ptr_)#{"." << member if member})"
    fmt = STRING_OR_FAILED_FORMAT
    checking_for checking_message("size of #{type}", headers), fmt do
      if size = try_constant(expr, prelude, opts, &b)
        $defs.push(format("-DSIZEOF_%s=%s", type.tr_cpp, size))
        size
      end
    end
  end

  # Returns the signedness of the given +type+.  You may optionally specify
  # additional +headers+ to search in for the +type+.
  #
  # If the +type+ is found and is a numeric type, a macro is passed as a
  # preprocessor constant to the compiler using the +type+ name, in uppercase,
  # prepended with +SIGNEDNESS_OF_+, followed by the +type+ name, followed by
  # <code>=X</code> where "X" is positive integer if the +type+ is unsigned
  # and a negative integer if the +type+ is signed.
  #
  # For example, if +size_t+ is defined as unsigned, then
  # <code>check_signedness('size_t')</code> would return +1 and the
  # <code>SIGNEDNESS_OF_SIZE_T=+1</code> preprocessor macro would be passed to
  # the compiler.  The <code>SIGNEDNESS_OF_INT=-1</code> macro would be set
  # for <code>check_signedness('int')</code>
  #
  def check_signedness(type, headers = nil, opts = nil, &b)
    typedef, member, prelude = typedef_expr(type, headers)
    signed = nil
    checking_for("signedness of #{type}", STRING_OR_FAILED_FORMAT) do
      signed = try_signedness(typedef, member, [prelude], opts, &b) or next nil
      $defs.push("-DSIGNEDNESS_OF_%s=%+d" % [type.tr_cpp, signed])
      signed < 0 ? "signed" : "unsigned"
    end
    signed
  end

  # Returns the convertible integer type of the given +type+.  You may
  # optionally specify additional +headers+ to search in for the +type+.
  # _convertible_ means actually the same type, or typedef'd from the same
  # type.
  #
  # If the +type+ is an integer type and the _convertible_ type is found,
  # the following macros are passed as preprocessor constants to the compiler
  # using the +type+ name, in uppercase.
  #
  # * +TYPEOF_+, followed by the +type+ name, followed by <code>=X</code>
  #   where "X" is the found _convertible_ type name.
  # * +TYP2NUM+ and +NUM2TYP+,
  #   where +TYP+ is the +type+ name in uppercase with replacing an +_t+
  #   suffix with "T", followed by <code>=X</code> where "X" is the macro name
  #   to convert +type+ to an Integer object, and vice versa.
  #
  # For example, if +foobar_t+ is defined as unsigned long, then
  # <code>convertible_int("foobar_t")</code> would return "unsigned long", and
  # define these macros:
  #
  #   #define TYPEOF_FOOBAR_T unsigned long
  #   #define FOOBART2NUM ULONG2NUM
  #   #define NUM2FOOBART NUM2ULONG
  #
  def convertible_int(type, headers = nil, opts = nil, &b)
    type, macname = *type
    checking_for("convertible type of #{type}", STRING_OR_FAILED_FORMAT) do
      if UNIVERSAL_INTS.include?(type)
        type
      else
        typedef, member, prelude = typedef_expr(type, headers, &b)
        if member
          prelude << "static rbcv_typedef_ rbcv_var;"
          compat = UNIVERSAL_INTS.find {|t|
            try_static_assert("sizeof(rbcv_var.#{member}) == sizeof(#{t})", [prelude], opts, &b)
          }
        else
          next unless signed = try_signedness(typedef, member, [prelude])
          u = "unsigned " if signed > 0
          prelude << "extern rbcv_typedef_ foo();"
          compat = UNIVERSAL_INTS.find {|t|
            try_compile([prelude, "extern #{u}#{t} foo();"].join("\n"), opts, :werror=>true, &b)
          }
        end
        if compat
          macname ||= type.sub(/_(?=t\z)/, '').tr_cpp
          conv = (compat == "long long" ? "LL" : compat.upcase)
          compat = "#{u}#{compat}"
          typename = type.tr_cpp
          $defs.push(format("-DSIZEOF_%s=SIZEOF_%s", typename, compat.tr_cpp))
          $defs.push(format("-DTYPEOF_%s=%s", typename, compat.quote))
          $defs.push(format("-DPRI_%s_PREFIX=PRI_%s_PREFIX", macname, conv))
          conv = (u ? "U" : "") + conv
          $defs.push(format("-D%s2NUM=%s2NUM", macname, conv))
          $defs.push(format("-DNUM2%s=NUM2%s", macname, conv))
          compat
        end
      end
    end
  end
  # :stopdoc:

  # Used internally by the what_type? method to determine if +type+ is a scalar
  # pointer.
  def scalar_ptr_type?(type, member = nil, headers = nil, &b)
    try_compile(<<"SRC", &b)   # pointer
#{cpp_include(headers)}
/*top*/
volatile #{type} conftestval;
extern int t(void);
#{MAIN_DOES_NOTHING 't'}
int t(void) {return (int)(1-*(conftestval#{member ? ".#{member}" : ""}));}
SRC
  end

  # Used internally by the what_type? method to determine if +type+ is a scalar
  # pointer.
  def scalar_type?(type, member = nil, headers = nil, &b)
    try_compile(<<"SRC", &b)   # pointer
#{cpp_include(headers)}
/*top*/
volatile #{type} conftestval;
extern int t(void);
#{MAIN_DOES_NOTHING 't'}
int t(void) {return (int)(1-(conftestval#{member ? ".#{member}" : ""}));}
SRC
  end

  # Used internally by the what_type? method to check if the _typeof_ GCC
  # extension is available.
  def have_typeof?
    return $typeof if defined?($typeof)
    $typeof = %w[__typeof__ typeof].find do |t|
      try_compile(<<SRC)
int rbcv_foo;
#{t}(rbcv_foo) rbcv_bar;
SRC
    end
  end

  def what_type?(type, member = nil, headers = nil, &b)
    m = "#{type}"
    var = val = "*rbcv_var_"
    func = "rbcv_func_(void)"
    if member
      m << "." << member
    else
      type, member = type.split('.', 2)
    end
    if member
      val = "(#{var}).#{member}"
    end
    prelude = [cpp_include(headers).split(/^/)]
    prelude << ["typedef #{type} rbcv_typedef_;\n",
                "extern rbcv_typedef_ *#{func};\n",
                "rbcv_typedef_ #{var};\n",
               ]
    type = "rbcv_typedef_"
    fmt = member && !(typeof = have_typeof?) ? "seems %s" : "%s"
    if typeof
      var = "*rbcv_member_"
      func = "rbcv_mem_func_(void)"
      member = nil
      type = "rbcv_mem_typedef_"
      prelude[-1] << "typedef #{typeof}(#{val}) #{type};\n"
      prelude[-1] << "extern #{type} *#{func};\n"
      prelude[-1] << "#{type} #{var};\n"
      val = var
    end
    def fmt.%(x)
      x ? super : "unknown"
    end
    checking_for checking_message(m, headers), fmt do
      if scalar_ptr_type?(type, member, prelude, &b)
        if try_static_assert("sizeof(*#{var}) == 1", prelude)
          return "string"
        end
        ptr = "*"
      elsif scalar_type?(type, member, prelude, &b)
        unless member and !typeof or try_static_assert("(#{type})-1 < 0", prelude)
          unsigned = "unsigned"
        end
        ptr = ""
      else
        next
      end
      type = UNIVERSAL_INTS.find do |t|
        pre = prelude
        unless member
          pre += [["#{unsigned} #{t} #{ptr}#{var};\n",
                   "extern #{unsigned} #{t} #{ptr}*#{func};\n"]]
        end
        try_static_assert("sizeof(#{ptr}#{val}) == sizeof(#{unsigned} #{t})", pre)
      end
      type or next
      [unsigned, type, ptr].join(" ").strip
    end
  end

  # This method is used internally by the find_executable method.
  #
  # Internal use only.
  #
  def find_executable0(bin, path = nil)
    executable_file = proc do |name|
      begin
        stat = File.stat(name)
      rescue SystemCallError
      else
        next name if stat.file? and stat.executable?
      end
    end

    exts = config_string('EXECUTABLE_EXTS') {|s| s.split} || config_string('EXEEXT') {|s| [s]}
    if File.expand_path(bin) == bin
      return bin if executable_file.call(bin)
      if exts
        exts.each {|ext| executable_file.call(file = bin + ext) and return file}
      end
      return nil
    end
    if path ||= ENV['PATH']
      path = path.split(File::PATH_SEPARATOR)
    else
      path = %w[/usr/local/bin /usr/ucb /usr/bin /bin]
    end
    file = nil
    path.each do |dir|
      dir.sub!(/\A"(.*)"\z/m, '\1') if $mswin or $mingw
      return file if executable_file.call(file = File.join(dir, bin))
      if exts
        exts.each {|ext| executable_file.call(ext = file + ext) and return ext}
      end
    end
    nil
  end

  # :startdoc:

  # Searches for the executable +bin+ on +path+.  The default path is your
  # +PATH+ environment variable. If that isn't defined, it will resort to
  # searching /usr/local/bin, /usr/ucb, /usr/bin and /bin.
  #
  # If found, it will return the full path, including the executable name, of
  # where it was found.
  #
  # Note that this method does not actually affect the generated Makefile.
  #
  def find_executable(bin, path = nil)
    checking_for checking_message(bin, path) do
      find_executable0(bin, path)
    end
  end

  # :stopdoc:

  def arg_config(config, default=nil, &block)
    $arg_config << [config, default]
    defaults = []
    if default
      defaults << default
    elsif !block
      defaults << nil
    end
    $configure_args.fetch(config.tr('_', '-'), *defaults, &block)
  end

  # :startdoc:

  # Tests for the presence of a <tt>--with-</tt>_config_ or
  # <tt>--without-</tt>_config_ option.  Returns +true+ if the with option is
  # given, +false+ if the without option is given, and the default value
  # otherwise.
  #
  # This can be useful for adding custom definitions, such as debug
  # information.
  #
  # Example:
  #
  #    if with_config("debug")
  #       $defs.push("-DOSSL_DEBUG") unless $defs.include? "-DOSSL_DEBUG"
  #    end
  #
  def with_config(config, default=nil)
    config = config.sub(/^--with[-_]/, '')
    val = arg_config("--with-"+config) do
      if arg_config("--without-"+config)
        false
      elsif block_given?
        yield(config, default)
      else
        break default
      end
    end
    case val
    when "yes"
      true
    when "no"
      false
    else
      val
    end
  end

  # Tests for the presence of an <tt>--enable-</tt>_config_ or
  # <tt>--disable-</tt>_config_ option. Returns +true+ if the enable option is
  # given, +false+ if the disable option is given, and the default value
  # otherwise.
  #
  # This can be useful for adding custom definitions, such as debug
  # information.
  #
  # Example:
  #
  #    if enable_config("debug")
  #       $defs.push("-DOSSL_DEBUG") unless $defs.include? "-DOSSL_DEBUG"
  #    end
  #
  def enable_config(config, default=nil)
    if arg_config("--enable-"+config)
      true
    elsif arg_config("--disable-"+config)
      false
    elsif block_given?
      yield(config, default)
    else
      return default
    end
  end

  # Generates a header file consisting of the various macro definitions
  # generated by other methods such as have_func and have_header. These are
  # then wrapped in a custom <code>#ifndef</code> based on the +header+ file
  # name, which defaults to "extconf.h".
  #
  # For example:
  #
  #   # extconf.rb
  #   require 'mkmf'
  #   have_func('realpath')
  #   have_header('sys/utime.h')
  #   create_header
  #   create_makefile('foo')
  #
  # The above script would generate the following extconf.h file:
  #
  #   #ifndef EXTCONF_H
  #   #define EXTCONF_H
  #   #define HAVE_REALPATH 1
  #   #define HAVE_SYS_UTIME_H 1
  #   #endif
  #
  # Given that the create_header method generates a file based on definitions
  # set earlier in your extconf.rb file, you will probably want to make this
  # one of the last methods you call in your script.
  #
  def create_header(header = "extconf.h")
    message "creating %s\n", header
    sym = header.tr_cpp
    hdr = ["#ifndef #{sym}\n#define #{sym}\n"]
    for line in $defs
      case line
      when /^-D([^=]+)(?:=(.*))?/
        hdr << "#define #$1 #{$2 ? Shellwords.shellwords($2)[0].gsub(/(?=\t+)/, "\\\n") : 1}\n"
      when /^-U(.*)/
        hdr << "#undef #$1\n"
      end
    end
    hdr << "#endif\n"
    hdr = hdr.join("")
    log_src(hdr, "#{header} is")
    unless (File.read(header) == hdr rescue false)
      File.open(header, "wb") do |hfile|
        hfile.write(hdr)
      end
    end
    $extconf_h = header
  end

  # call-seq:
  #   dir_config(target)
  #   dir_config(target, prefix)
  #   dir_config(target, idefault, ldefault)
  #
  # Sets a +target+ name that the user can then use to configure
  # various "with" options with on the command line by using that
  # name.  For example, if the target is set to "foo", then the user
  # could use the <code>--with-foo-dir=prefix</code>,
  # <code>--with-foo-include=dir</code> and
  # <code>--with-foo-lib=dir</code> command line options to tell where
  # to search for header/library files.
  #
  # You may pass along additional parameters to specify default
  # values.  If one is given it is taken as default +prefix+, and if
  # two are given they are taken as "include" and "lib" defaults in
  # that order.
  #
  # In any case, the return value will be an array of determined
  # "include" and "lib" directories, either of which can be nil if no
  # corresponding command line option is given when no default value
  # is specified.
  #
  # Note that dir_config only adds to the list of places to search for
  # libraries and include files.  It does not link the libraries into your
  # application.
  #
  def dir_config(target, idefault=nil, ldefault=nil)
    key = [target, idefault, ldefault].compact.join("\0")
    if conf = $config_dirs[key]
      return conf
    end

    if dir = with_config(target + "-dir", (idefault unless ldefault))
      defaults = Array === dir ? dir : dir.split(File::PATH_SEPARATOR)
      idefault = ldefault = nil
    end

    idir = with_config(target + "-include", idefault)
    if conf = $arg_config.assoc("--with-#{target}-include")
      conf[1] ||= "${#{target}-dir}/include"
    end
    ldir = with_config(target + "-lib", ldefault)
    if conf = $arg_config.assoc("--with-#{target}-lib")
      conf[1] ||= "${#{target}-dir}/#{_libdir_basename}"
    end

    idirs = idir ? Array === idir ? idir.dup : idir.split(File::PATH_SEPARATOR) : []
    if defaults
      idirs.concat(defaults.collect {|d| d + "/include"})
      idir = ([idir] + idirs).compact.join(File::PATH_SEPARATOR)
    end
    unless idirs.empty?
      idirs.collect! {|d| "-I" + d}
      idirs -= Shellwords.shellwords($CPPFLAGS)
      unless idirs.empty?
        $CPPFLAGS = (idirs.quote << $CPPFLAGS).join(" ")
      end
    end

    ldirs = ldir ? Array === ldir ? ldir.dup : ldir.split(File::PATH_SEPARATOR) : []
    if defaults
      ldirs.concat(defaults.collect {|d| "#{d}/#{_libdir_basename}"})
      ldir = ([ldir] + ldirs).compact.join(File::PATH_SEPARATOR)
    end
    $LIBPATH = ldirs | $LIBPATH

    $config_dirs[key] = [idir, ldir]
  end

  # Returns compile/link information about an installed library in a tuple of <code>[cflags,
  # ldflags, libs]</code>, by using the command found first in the following commands:
  #
  # 1. If <code>--with-{pkg}-config={command}</code> is given via
  #    command line option: <code>{command} {options}</code>
  #
  # 2. <code>{pkg}-config {options}</code>
  #
  # 3. <code>pkg-config {options} {pkg}</code>
  #
  # Where +options+ is the option name without dashes, for instance <code>"cflags"</code> for the
  # <code>--cflags</code> flag.
  #
  # The values obtained are appended to <code>$INCFLAGS</code>, <code>$CFLAGS</code>,
  # <code>$LDFLAGS</code> and <code>$libs</code>.
  #
  # If one or more <code>options</code> argument is given, the config command is
  # invoked with the options and a stripped output string is returned without
  # modifying any of the global values mentioned above.
  def pkg_config(pkg, *options)
    fmt = "not found"
    def fmt.%(x)
      x ? x.inspect : self
    end

    checking_for "pkg-config for #{pkg}", fmt do
      _, ldir = dir_config(pkg)
      if ldir
        pkg_config_path = "#{ldir}/pkgconfig"
        if File.directory?(pkg_config_path)
          Logging.message("PKG_CONFIG_PATH = %s\n", pkg_config_path)
          envs = ["PKG_CONFIG_PATH"=>[pkg_config_path, ENV["PKG_CONFIG_PATH"]].compact.join(File::PATH_SEPARATOR)]
        end
      end
      if pkgconfig = with_config("#{pkg}-config") and find_executable0(pkgconfig)
      # if and only if package specific config command is given
      elsif ($PKGCONFIG ||=
             (pkgconfig = with_config("pkg-config") {config_string("PKG_CONFIG") || "pkg-config"}) &&
             find_executable0(pkgconfig) && pkgconfig) and
           xsystem([*envs, $PKGCONFIG, "--exists", pkg])
        # default to pkg-config command
        pkgconfig = $PKGCONFIG
        args = [pkg]
      elsif find_executable0(pkgconfig = "#{pkg}-config")
      # default to package specific config command, as a last resort.
      else
        pkgconfig = nil
      end
      if pkgconfig
        get = proc {|opts|
          opts = Array(opts).map { |o| "--#{o}" }
          opts = xpopen([*envs, pkgconfig, *opts, *args], err:[:child, :out], &:read)
          Logging.open {puts opts.each_line.map{|s|"=> #{s.inspect}"}}
          opts.strip if $?.success?
        }
      end
      orig_ldflags = $LDFLAGS
      if get and !options.empty?
        get[options]
      elsif get and try_ldflags(ldflags = get['libs'])
        if incflags = get['cflags-only-I']
          $INCFLAGS << " " << incflags
          cflags = get['cflags-only-other']
        else
          cflags = get['cflags']
        end
        libs = get['libs-only-l']
        if cflags
          $CFLAGS += " " << cflags
          $CXXFLAGS += " " << cflags
        end
        if libs
          ldflags = (Shellwords.shellwords(ldflags) - Shellwords.shellwords(libs)).quote.join(" ")
        else
          libs, ldflags = Shellwords.shellwords(ldflags).partition {|s| s =~ /-l([^ ]+)/ }.map {|l|l.quote.join(" ")}
        end
        $libs += " " << libs

        $LDFLAGS = [orig_ldflags, ldflags].join(' ')
        Logging::message "package configuration for %s\n", pkg
        Logging::message "incflags: %s\ncflags: %s\nldflags: %s\nlibs: %s\n\n",
                         incflags, cflags, ldflags, libs
        [[incflags, cflags].join(' '), ldflags, libs]
      else
        Logging::message "package configuration for %s is not found\n", pkg
        nil
      end
    end
  end

  # :stopdoc:

  def with_destdir(dir)
    dir = dir.sub($dest_prefix_pattern, '')
    /\A\$[\(\{]/ =~ dir ? dir : "$(DESTDIR)"+dir
  end

  # Converts forward slashes to backslashes. Aimed at MS Windows.
  #
  # Internal use only.
  #
  def winsep(s)
    s.tr('/', '\\')
  end

  # Converts native path to format acceptable in Makefile
  #
  # Internal use only.
  #
  if !CROSS_COMPILING
    case CONFIG['build_os']
    when 'mingw32'
      def mkintpath(path)
        # mingw uses make from msys and it needs special care
        # converts from C:\some\path to /C/some/path
        path = path.dup
        path.tr!('\\', '/')
        path.sub!(/\A([A-Za-z]):(?=\/)/, '/\1')
        path
      end
    when 'cygwin', 'msys'
      if CONFIG['target_os'] != 'cygwin'
        def mkintpath(path)
          IO.popen(["cygpath", "-u", path], &:read).chomp
        end
      end
    end
  end
  unless method_defined?(:mkintpath)
    def mkintpath(path)
      path
    end
  end

  def configuration(srcdir)
    mk = []
    verbose = with_config('verbose') ?  "1" : (CONFIG['MKMF_VERBOSE'] || "0")
    vpath = $VPATH.dup
    CONFIG["hdrdir"] ||= $hdrdir
    mk << %{
SHELL = /bin/sh

# V=0 quiet, V=1 verbose.  other values don't work.
V = #{verbose}
V0 = $(V:0=)
Q1 = $(V:1=)
Q = $(Q1:0=@)
ECHO1 = $(V:1=@ #{CONFIG['NULLCMD']})
ECHO = $(ECHO1:0=@ echo)
NULLCMD = #{CONFIG['NULLCMD']}

#### Start of system configuration section. ####
#{"top_srcdir = " + $top_srcdir.sub(%r"\A#{Regexp.quote($topdir)}/", "$(topdir)/") if $extmk}
srcdir = #{srcdir.gsub(/\$\((srcdir)\)|\$\{(srcdir)\}/) {mkintpath(CONFIG[$1||$2]).unspace}}
topdir = #{mkintpath(topdir = $extmk ? CONFIG["topdir"] : $topdir).unspace}
hdrdir = #{(hdrdir = CONFIG["hdrdir"]) == topdir ? "$(topdir)" : mkintpath(hdrdir).unspace}
arch_hdrdir = #{mkintpath($arch_hdrdir).unspace}
PATH_SEPARATOR = #{CONFIG['PATH_SEPARATOR']}
VPATH = #{vpath.join(CONFIG['PATH_SEPARATOR'])}
}
    if $extmk
      mk << "RUBYLIB =\n""RUBYOPT = -\n"
    end
    prefix = mkintpath(CONFIG["prefix"])
    if destdir = prefix[$dest_prefix_pattern, 1]
      mk << "\nDESTDIR = #{destdir}\n"
      prefix = prefix[destdir.size..-1]
    end
    mk << "prefix = #{with_destdir(prefix).unspace}\n"
    CONFIG.each do |key, var|
      mk << "#{key} = #{with_destdir(mkintpath(var)).unspace}\n" if /.prefix$/ =~ key
    end
    CONFIG.each do |key, var|
      next if /^abs_/ =~ key
      next if /^(?:src|top(?:_src)?|build|hdr)dir$/ =~ key
      next unless /dir$/ =~ key
      mk << "#{key} = #{with_destdir(var)}\n"
    end
    if !$extmk and !$configure_args.has_key?('--ruby') and
        sep = config_string('BUILD_FILE_SEPARATOR')
      sep = ":/=#{sep}"
    else
      sep = ""
    end
    possible_command = (proc {|s| s if /top_srcdir|tooldir/ !~ s} unless $extmk)
    extconf_h = $extconf_h ? "-DRUBY_EXTCONF_H=\\\"$(RUBY_EXTCONF_H)\\\" " : $defs.join(" ") << " "
    headers = %w[
      $(hdrdir)/ruby.h
      $(hdrdir)/ruby/backward.h
      $(hdrdir)/ruby/ruby.h
      $(hdrdir)/ruby/defines.h
      $(hdrdir)/ruby/missing.h
      $(hdrdir)/ruby/intern.h
      $(hdrdir)/ruby/st.h
      $(hdrdir)/ruby/subst.h
    ]
    headers += $headers
    if RULE_SUBST
      headers.each {|h| h.sub!(/.*/, &RULE_SUBST.method(:%))}
    end
    headers << $config_h
    headers << '$(RUBY_EXTCONF_H)' if $extconf_h
    mk << %{

CC_WRAPPER = #{CONFIG['CC_WRAPPER']}
CC = #{CONFIG['CC']}
CXX = #{CONFIG['CXX']}
LIBRUBY = #{CONFIG['LIBRUBY']}
LIBRUBY_A = #{CONFIG['LIBRUBY_A']}
LIBRUBYARG_SHARED = #$LIBRUBYARG_SHARED
LIBRUBYARG_STATIC = #$LIBRUBYARG_STATIC
empty =
OUTFLAG = #{OUTFLAG}$(empty)
COUTFLAG = #{COUTFLAG}$(empty)
CSRCFLAG = #{CSRCFLAG}$(empty)

RUBY_EXTCONF_H = #{$extconf_h}
cflags   = #{CONFIG['cflags']}
cxxflags = #{CONFIG['cxxflags']}
optflags = #{CONFIG['optflags']}
debugflags = #{CONFIG['debugflags']}
warnflags = #{$warnflags}
cppflags = #{CONFIG['cppflags']}
CCDLFLAGS = #{$static ? '' : CONFIG['CCDLFLAGS']}
CFLAGS   = $(CCDLFLAGS) #$CFLAGS $(ARCH_FLAG)
INCFLAGS = -I. #$INCFLAGS
DEFS     = #{CONFIG['DEFS']}
CPPFLAGS = #{extconf_h}#{$CPPFLAGS}
CXXFLAGS = $(CCDLFLAGS) #$CXXFLAGS $(ARCH_FLAG)
ldflags  = #{$LDFLAGS}
dldflags = #{$DLDFLAGS} #{CONFIG['EXTDLDFLAGS']}
ARCH_FLAG = #{$ARCH_FLAG}
DLDFLAGS = $(ldflags) $(dldflags) $(ARCH_FLAG)
LDSHARED = #{CONFIG['LDSHARED']}
LDSHAREDXX = #{config_string('LDSHAREDXX') || '$(LDSHARED)'}
AR = #{CONFIG['AR']}
EXEEXT = #{CONFIG['EXEEXT']}

}
    CONFIG.each do |key, val|
      mk << "#{key} = #{val}\n" if /^RUBY.*NAME/ =~ key
    end
    mk << %{
arch = #{CONFIG['arch']}
sitearch = #{CONFIG['sitearch']}
ruby_version = #{RbConfig::CONFIG['ruby_version']}
ruby = #{$ruby.sub(%r[\A#{Regexp.quote(RbConfig::CONFIG['bindir'])}(?=/|\z)]) {'$(bindir)'}}
RUBY = $(ruby#{sep})
BUILTRUBY = #{if defined?($builtruby) && $builtruby
    $builtruby
  else
    File.join('$(bindir)', CONFIG["RUBY_INSTALL_NAME"] + CONFIG['EXEEXT'])
  end}
ruby_headers = #{headers.join(' ')}

RM = #{config_string('RM', &possible_command) || '$(RUBY) -run -e rm -- -f'}
RM_RF = #{config_string('RMALL', &possible_command) || '$(RUBY) -run -e rm -- -rf'}
RMDIRS = #{config_string('RMDIRS', &possible_command) || '$(RUBY) -run -e rmdir -- -p'}
MAKEDIRS = #{config_string('MAKEDIRS', &possible_command) || '@$(RUBY) -run -e mkdir -- -p'}
INSTALL = #{config_string('INSTALL', &possible_command) || '@$(RUBY) -run -e install -- -vp'}
INSTALL_PROG = #{config_string('INSTALL_PROG') || '$(INSTALL) -m 0755'}
INSTALL_DATA = #{config_string('INSTALL_DATA') || '$(INSTALL) -m 0644'}
COPY = #{config_string('CP', &possible_command) || '@$(RUBY) -run -e cp -- -v'}
TOUCH = exit >

#### End of system configuration section. ####

preload = #{defined?($preload) && $preload ? $preload.join(' ') : ''}
}
    mk
  end

  def timestamp_file(name, target_prefix = nil)
    pat = {}
    name = '$(RUBYARCHDIR)' if name == '$(TARGET_SO_DIR)'
    install_dirs.each do |n, d|
      pat[n] = $` if /\$\(target_prefix\)\z/ =~ d
    end
    name = name.gsub(/\$\((#{pat.keys.join("|")})\)/) {pat[$1]+target_prefix}
    name.sub!(/(\$\((?:site)?arch\))\/*/, '')
    arch = $1 || ''
    name.chomp!('/')
    name = name.gsub(/(\$[({]|[})])|(\/+)|[^-.\w]+/) {$1 ? "" : $2 ? ".-." : "_"}
    File.join("$(TIMESTAMP_DIR)", arch, "#{name.sub(/\A(?=.)/, '.')}.time")
  end
  # :startdoc:

  # Creates a stub Makefile.
  #
  def dummy_makefile(srcdir)
    configuration(srcdir) << <<RULES << CLEANINGS
CLEANFILES = #{$cleanfiles.join(' ')}
DISTCLEANFILES = #{$distcleanfiles.join(' ')}

all install static install-so install-rb: Makefile
	@$(NULLCMD)
.PHONY: all install static install-so install-rb
.PHONY: clean clean-so clean-static clean-rb

RULES
  end

  def each_compile_rules # :nodoc:
    vpath_splat = /\$\(\*VPATH\*\)/
    COMPILE_RULES.each do |rule|
      if vpath_splat =~ rule
        $VPATH.each do |path|
          yield rule.sub(vpath_splat) {path}
        end
      else
        yield rule
      end
    end
  end

  # Processes the data contents of the "depend" file.  Each line of this file
  # is expected to be a file name.
  #
  # Returns the output of findings, in Makefile format.
  #
  def depend_rules(depend)
    suffixes = []
    depout = []
    cont = implicit = nil
    impconv = proc do
      each_compile_rules {|rule| depout << (rule % implicit[0]) << implicit[1]}
      implicit = nil
    end
    ruleconv = proc do |line|
      if implicit
        if /\A\t/ =~ line
          implicit[1] << line
          next
        else
          impconv[]
        end
      end
      if m = /\A\.(\w+)\.(\w+)(?:\s*:)/.match(line)
        suffixes << m[1] << m[2]
        implicit = [[m[1], m[2]], [m.post_match]]
        next
      elsif RULE_SUBST and /\A(?!\s*\w+\s*=)[$\w][^#]*:/ =~ line
        line.sub!(/\s*\#.*$/, '')
        comment = $&
        line.gsub!(%r"(\s)(?!\.)([^$(){}+=:\s\\,]+)(?=\s|\z)") {$1 + RULE_SUBST % $2}
        line = line.chomp + comment + "\n" if comment
      end
      depout << line
    end
    depend.each_line do |line|
      line.gsub!(/\.o\b/, ".#{$OBJEXT}")
      line.gsub!(/\{\$\(VPATH\)\}/, "") unless $nmake
      line.gsub!(/\$\((?:hdr|top)dir\)\/config.h/, $config_h)
      if $nmake && /\A\s*\$\(RM|COPY\)/ =~ line
        line.gsub!(%r"[-\w\./]{2,}"){$&.tr("/", "\\")}
        line.gsub!(/(\$\((?!RM|COPY)[^:)]+)(?=\))/, '\1:/=\\')
      end
      if /(?:^|[^\\])(?:\\\\)*\\$/ =~ line
        (cont ||= []) << line
        next
      elsif cont
        line = (cont << line).join
        cont = nil
      end
      ruleconv.call(line)
    end
    if cont
      ruleconv.call(cont.join)
    elsif implicit
      impconv.call
    end
    unless suffixes.empty?
      depout.unshift(".SUFFIXES: ." + suffixes.uniq.join(" .") + "\n\n")
    end
    if $extconf_h
      depout.unshift("$(OBJS): $(RUBY_EXTCONF_H)\n\n")
      depout.unshift("$(OBJS): $(hdrdir)/ruby/win32.h\n\n") if $mswin or $mingw
    end
    depout.flatten!
    depout
  end

  # Generates the Makefile for your extension, passing along any options and
  # preprocessor constants that you may have generated through other methods.
  #
  # The +target+ name should correspond the name of the global function name
  # defined within your C extension, minus the +Init_+.  For example, if your
  # C extension is defined as +Init_foo+, then your target would simply be
  # "foo".
  #
  # If any "/" characters are present in the target name, only the last name
  # is interpreted as the target name, and the rest are considered toplevel
  # directory names, and the generated Makefile will be altered accordingly to
  # follow that directory structure.
  #
  # For example, if you pass "test/foo" as a target name, your extension will
  # be installed under the "test" directory.  This means that in order to
  # load the file within a Ruby program later, that directory structure will
  # have to be followed, e.g. <code>require 'test/foo'</code>.
  #
  # The +srcprefix+ should be used when your source files are not in the same
  # directory as your build script. This will not only eliminate the need for
  # you to manually copy the source files into the same directory as your
  # build script, but it also sets the proper +target_prefix+ in the generated
  # Makefile.
  #
  # Setting the +target_prefix+ will, in turn, install the generated binary in
  # a directory under your <code>RbConfig::CONFIG['sitearchdir']</code> that
  # mimics your local filesystem when you run <code>make install</code>.
  #
  # For example, given the following file tree:
  #
  #   ext/
  #     extconf.rb
  #     test/
  #       foo.c
  #
  # And given the following code:
  #
  #   create_makefile('test/foo', 'test')
  #
  # That will set the +target_prefix+ in the generated Makefile to "test".
  # That, in turn, will create the following file tree when installed via the
  # <code>make install</code> command:
  #
  #   /path/to/ruby/sitearchdir/test/foo.so
  #
  # It is recommended that you use this approach to generate your makefiles,
  # instead of copying files around manually, because some third party
  # libraries may depend on the +target_prefix+ being set properly.
  #
  # The +srcprefix+ argument can be used to override the default source
  # directory, i.e. the current directory.  It is included as part of the
  # +VPATH+ and added to the list of +INCFLAGS+.
  #
  def create_makefile(target, srcprefix = nil)
    $target = target
    libpath = $DEFLIBPATH|$LIBPATH
    message "creating Makefile\n"
    MakeMakefile.rm_f "#{CONFTEST}*"
    if CONFIG["DLEXT"] == $OBJEXT
      for lib in libs = $libs.split(' ')
        lib.sub!(/-l(.*)/, %%"lib\\1.#{$LIBEXT}"%)
      end
      $defs.push(format("-DEXTLIB='%s'", libs.join(",")))
    end

    if target.include?('/')
      target_prefix, target = File.split(target)
      target_prefix[0,0] = '/'
    else
      target_prefix = ""
    end

    srcprefix ||= "$(srcdir)/#{srcprefix}".chomp('/')
    RbConfig.expand(srcdir = srcprefix.dup)

    ext = ".#{$OBJEXT}"
    orig_srcs = Dir[File.join(srcdir, "*.{#{SRC_EXT.join(%q{,})}}")]
    if not $objs
      srcs = $srcs || orig_srcs
      $objs = []
      objs = srcs.inject(Hash.new {[]}) {|h, f|
        h.key?(o = File.basename(f, ".*") << ext) or $objs << o
        h[o] <<= f
        h
      }
      unless objs.delete_if {|b, f| f.size == 1}.empty?
        dups = objs.map {|b, f|
          "#{b[/.*\./]}{#{f.collect {|n| n[/([^.]+)\z/]}.join(',')}}"
        }
        abort "source files duplication - #{dups.join(", ")}"
      end
    else
      $objs.collect! {|o| File.basename(o, ".*") << ext} unless $OBJEXT == "o"
      srcs = $srcs || $objs.collect {|o| o.chomp(ext) << ".c"}
    end
    $srcs = srcs

    hdrs = Dir[File.join(srcdir, "*.{#{HDR_EXT.join(%q{,})}}")]

    target = nil if $objs.empty?

    if target and EXPORT_PREFIX
      if File.exist?(File.join(srcdir, target + '.def'))
        deffile = "$(srcdir)/$(TARGET).def"
        unless EXPORT_PREFIX.empty?
          makedef = %{$(RUBY) -pe "$$_.sub!(/^(?=\\w)/,'#{EXPORT_PREFIX}') unless 1../^EXPORTS$/i" #{deffile}}
        end
      else
        makedef = %{(echo EXPORTS && echo $(TARGET_ENTRY))}
      end
      if makedef
        $cleanfiles << '$(DEFFILE)'
        origdef = deffile
        deffile = "$(TARGET)-$(arch).def"
      end
    end
    origdef ||= ''

    if $extout and $INSTALLFILES
      $cleanfiles.concat($INSTALLFILES.collect {|files, dir|File.join(dir, files.delete_prefix('./'))})
      $distcleandirs.concat($INSTALLFILES.collect {|files, dir| dir})
    end

    if $extmk and $static
      $defs << "-DRUBY_EXPORT=1"
    end

    if $extmk and not $extconf_h
      create_header
    end

    libpath = libpathflag(libpath)

    dllib = target ? "$(TARGET).#{CONFIG['DLEXT']}" : ""
    staticlib = target ? "$(TARGET).#$LIBEXT" : ""
    conf = configuration(srcprefix)
    conf << "\
libpath = #{($DEFLIBPATH|$LIBPATH).join(" ")}
LIBPATH = #{libpath}
DEFFILE = #{deffile}

CLEANFILES = #{$cleanfiles.join(' ')}
DISTCLEANFILES = #{$distcleanfiles.join(' ')}
DISTCLEANDIRS = #{$distcleandirs.join(' ')}

extout = #{$extout && $extout.quote}
extout_prefix = #{$extout_prefix}
target_prefix = #{target_prefix}
LOCAL_LIBS = #{$LOCAL_LIBS}
LIBS = #{$LIBRUBYARG} #{$libs} #{$LIBS}
ORIG_SRCS = #{orig_srcs.collect(&File.method(:basename)).join(' ')}
SRCS = $(ORIG_SRCS) #{(srcs - orig_srcs).collect(&File.method(:basename)).join(' ')}
OBJS = #{$objs.join(" ")}
HDRS = #{hdrs.map{|h| '$(srcdir)/' + File.basename(h)}.join(' ')}
LOCAL_HDRS = #{$headers.join(' ')}
TARGET = #{target}
TARGET_NAME = #{target && target[/\A\w+/]}
TARGET_ENTRY = #{EXPORT_PREFIX || ''}Init_$(TARGET_NAME)
DLLIB = #{dllib}
EXTSTATIC = #{$static || ""}
STATIC_LIB = #{staticlib unless $static.nil?}
#{!$extout && defined?($installed_list) ? "INSTALLED_LIST = #{$installed_list}\n" : ""}
TIMESTAMP_DIR = #{$extout && $extmk ? '$(extout)/.timestamp' : '.'}
" #"
    # TODO: fixme
    install_dirs.each {|d| conf << ("%-14s= %s\n" % d) if /^[[:upper:]]/ =~ d[0]}
    sodir = $extout ? '$(TARGET_SO_DIR)' : '$(RUBYARCHDIR)'
    n = '$(TARGET_SO_DIR)$(TARGET)'
    cleanobjs = ["$(OBJS)"]
    if $extmk
      %w[bc i s].each {|ex| cleanobjs << "$(OBJS:.#{$OBJEXT}=.#{ex})"}
    end
    if target
      config_string('cleanobjs') {|t| cleanobjs << t.gsub(/\$\*/, "$(TARGET)#{deffile ? '-$(arch)': ''}")}
    end
    conf << "\
TARGET_SO_DIR =#{$extout ? " $(RUBYARCHDIR)/" : ''}
TARGET_SO     = $(TARGET_SO_DIR)$(DLLIB)
CLEANLIBS     = #{'$(TARGET_SO) ' if target}#{config_string('cleanlibs') {|t| t.gsub(/\$\*/) {n}}}
CLEANOBJS     = #{cleanobjs.join(' ')} *.bak
TARGET_SO_DIR_TIMESTAMP = #{timestamp_file(sodir, target_prefix)}
" #"

    conf = yield(conf) if block_given?
    mfile = File.open("Makefile", "wb")
    mfile.puts(conf)
    mfile.print "
all:    #{$extout ? "install" : target ? "$(DLLIB)" : "Makefile"}
static: #{$extmk && !$static ? "all" : "$(STATIC_LIB)#{$extout ? " install-rb" : ""}"}
.PHONY: all install static install-so install-rb
.PHONY: clean clean-so clean-static clean-rb
" #"
    mfile.print CLEANINGS
    fsep = config_string('BUILD_FILE_SEPARATOR') {|s| s unless s == "/"}
    if fsep
      sep = ":/=#{fsep}"
      fseprepl = proc {|s|
        s = s.gsub("/", fsep)
        s = s.gsub(/(\$\(\w+)(\))/) {$1+sep+$2}
        s.gsub(/(\$\{\w+)(\})/) {$1+sep+$2}
      }
      rsep = ":#{fsep}=/"
    else
      fseprepl = proc {|s| s}
      sep = ""
      rsep = ""
    end
    dirs = []
    mfile.print "install: install-so install-rb\n\n"
    dir = sodir.dup
    mfile.print("install-so: ")
    if target
      f = "$(DLLIB)"
      dest = "$(TARGET_SO)"
      stamp = '$(TARGET_SO_DIR_TIMESTAMP)'
      if $extout
        mfile.puts dest
        mfile.print "clean-so::\n"
        mfile.print "\t-$(Q)$(RM) #{fseprepl[dest]} #{fseprepl[stamp]}\n"
        mfile.print "\t-$(Q)$(RMDIRS) #{fseprepl[dir]}#{$ignore_error}\n"
      else
        mfile.print "#{f} #{stamp}\n"
        mfile.print "\t$(INSTALL_PROG) #{fseprepl[f]} #{dir}\n"
        if defined?($installed_list)
          mfile.print "\t@echo #{dir}/#{File.basename(f)}>>$(INSTALLED_LIST)\n"
        end
      end
      mfile.print "clean-static::\n"
      mfile.print "\t-$(Q)$(RM) $(STATIC_LIB)\n"
    else
      mfile.puts "Makefile"
    end
    mfile.print("install-rb: pre-install-rb do-install-rb install-rb-default\n")
    mfile.print("install-rb-default: pre-install-rb-default do-install-rb-default\n")
    mfile.print("pre-install-rb: Makefile\n")
    mfile.print("pre-install-rb-default: Makefile\n")
    mfile.print("do-install-rb:\n")
    mfile.print("do-install-rb-default:\n")
    for sfx, i in [["-default", [["lib/**/*.rb", "$(RUBYLIBDIR)", "lib"]]], ["", $INSTALLFILES]]
      files = install_files(mfile, i, nil, srcprefix) or next
      for dir, *files in files
        unless dirs.include?(dir)
          dirs << dir
          mfile.print "pre-install-rb#{sfx}: #{timestamp_file(dir, target_prefix)}\n"
        end
        for f in files
          dest = "#{dir}/#{File.basename(f)}"
          mfile.print("do-install-rb#{sfx}: #{dest}\n")
          mfile.print("#{dest}: #{f} #{timestamp_file(dir, target_prefix)}\n")
          mfile.print("\t$(Q) $(#{$extout ? 'COPY' : 'INSTALL_DATA'}) #{f} $(@D)\n")
          if defined?($installed_list) and !$extout
            mfile.print("\t@echo #{dest}>>$(INSTALLED_LIST)\n")
          end
          if $extout
            mfile.print("clean-rb#{sfx}::\n")
            mfile.print("\t-$(Q)$(RM) #{fseprepl[dest]}\n")
          end
        end
      end
      mfile.print "pre-install-rb#{sfx}:\n"
      if files.empty?
        mfile.print("\t@$(NULLCMD)\n")
      else
        q = "$(MAKE) -q do-install-rb#{sfx}"
        if $nmake
          mfile.print "!if \"$(Q)\" == \"@\"\n\t@#{q} || \\\n!endif\n\t"
        else
          mfile.print "\t$(Q1:0=@#{q} || )"
        end
        mfile.print "$(ECHO1:0=echo) installing#{sfx.sub(/^-/, " ")} #{target} libraries\n"
      end
      if $extout
        dirs.uniq!
        unless dirs.empty?
          mfile.print("clean-rb#{sfx}::\n")
          for dir in dirs.sort_by {|d| -d.count('/')}
            stamp = timestamp_file(dir, target_prefix)
            mfile.print("\t-$(Q)$(RM) #{fseprepl[stamp]}\n")
            mfile.print("\t-$(Q)$(RMDIRS) #{fseprepl[dir]}#{$ignore_error}\n")
          end
        end
      end
    end
    if target and !dirs.include?(sodir)
      mfile.print "$(TARGET_SO_DIR_TIMESTAMP):\n\t$(Q) $(MAKEDIRS) $(@D) #{sodir}\n\t$(Q) $(TOUCH) $@\n"
    end
    dirs.each do |d|
      t = timestamp_file(d, target_prefix)
      mfile.print "#{t}:\n\t$(Q) $(MAKEDIRS) $(@D) #{d}\n\t$(Q) $(TOUCH) $@\n"
    end

    mfile.print <<-SITEINSTALL

site-install: site-install-so site-install-rb
site-install-so: install-so
site-install-rb: install-rb

    SITEINSTALL

    return unless target

    mfile.print ".SUFFIXES: .#{(SRC_EXT + [$OBJEXT, $ASMEXT]).compact.join(' .')}\n"
    mfile.print "\n"

    compile_command = "\n\t$(ECHO) compiling $(<#{rsep})\n\t$(Q) %s\n\n"
    command = compile_command % COMPILE_CXX
    asm_command = compile_command.sub(/compiling/, 'translating') % ASSEMBLE_CXX
    CXX_EXT.each do |e|
      each_compile_rules do |rule|
        mfile.printf(rule, e, $OBJEXT)
        mfile.print(command)
        mfile.printf(rule, e, $ASMEXT)
        mfile.print(asm_command)
      end
    end
    command = compile_command % COMPILE_C
    asm_command = compile_command.sub(/compiling/, 'translating') % ASSEMBLE_C
    C_EXT.each do |e|
      each_compile_rules do |rule|
        mfile.printf(rule, e, $OBJEXT)
        mfile.print(command)
        mfile.printf(rule, e, $ASMEXT)
        mfile.print(asm_command)
      end
    end

    mfile.print "$(TARGET_SO): "
    mfile.print "$(DEFFILE) " if makedef
    mfile.print "$(OBJS) Makefile"
    mfile.print " $(TARGET_SO_DIR_TIMESTAMP)" if $extout
    mfile.print "\n"
    mfile.print "\t$(ECHO) linking shared-object #{target_prefix.sub(/\A\/(.*)/, '\1/')}$(DLLIB)\n"
    mfile.print "\t-$(Q)$(RM) $(@#{sep})\n"
    link_so = LINK_SO.gsub(/^/, "\t$(Q) ")
    if srcs.any?(&%r"\.(?:#{CXX_EXT.join('|')})\z".method(:===))
      link_so = link_so.sub(/\bLDSHARED\b/, '\&XX')
    end
    mfile.print link_so, "\n\n"
    unless $static.nil?
      mfile.print "$(STATIC_LIB): $(OBJS)\n\t-$(Q)$(RM) $(@#{sep})\n\t"
      mfile.print "$(ECHO) linking static-library $(@#{rsep})\n\t$(Q) "
      mfile.print "$(AR) #{config_string('ARFLAGS') || 'cru '}$@ $(OBJS)"
      config_string('RANLIB') do |ranlib|
        mfile.print "\n\t-$(Q)#{ranlib} $(@)#{$ignore_error}"
      end
    end
    mfile.print "\n\n"
    if makedef
      mfile.print "$(DEFFILE): #{origdef}\n"
      mfile.print "\t$(ECHO) generating $(@#{rsep})\n"
      mfile.print "\t$(Q) #{makedef} > $@\n\n"
    end

    depend = File.join(srcdir, "depend")
    if File.exist?(depend)
      mfile.print("###\n", *depend_rules(File.read(depend)))
    else
      mfile.print "$(OBJS): $(HDRS) $(ruby_headers)\n"
    end

    $makefile_created = true
  ensure
    mfile.close if mfile
  end

  # :stopdoc:

  def init_mkmf(config = CONFIG, rbconfig = RbConfig::CONFIG)
    $makefile_created = false
    $arg_config = []
    $enable_shared = config['ENABLE_SHARED'] == 'yes'
    $defs = []
    $extconf_h = nil
    $config_dirs = {}

    if $warnflags = CONFIG['warnflags'] and CONFIG['GCC'] == 'yes'
      # turn warnings into errors only for bundled extensions.
      config['warnflags'] = $warnflags.gsub(/(?:\A|\s)-W\Kerror[-=](?!implicit-function-declaration)/, '')
      if /icc\z/ =~ config['CC']
        config['warnflags'].gsub!(/(\A|\s)-W(?:division-by-zero|deprecated-declarations)/, '\1')
      end
      RbConfig.expand(rbconfig['warnflags'] = config['warnflags'].dup)
      config.each do |key, val|
        RbConfig.expand(rbconfig[key] = val.dup) if /warnflags/ =~ val
      end
      $warnflags = config['warnflags'] unless $extmk
    end
    if (w = rbconfig['CC_WRAPPER']) and !w.empty? and !File.executable?(w)
      rbconfig['CC_WRAPPER'] = config['CC_WRAPPER'] = ''
    end
    $CFLAGS = with_config("cflags", arg_config("CFLAGS", config["CFLAGS"])).dup
    $CXXFLAGS = (with_config("cxxflags", arg_config("CXXFLAGS", config["CXXFLAGS"]))||'').dup
    $ARCH_FLAG = with_config("arch_flag", arg_config("ARCH_FLAG", config["ARCH_FLAG"])).dup
    $CPPFLAGS = with_config("cppflags", arg_config("CPPFLAGS", config["CPPFLAGS"])).dup
    $LDFLAGS = with_config("ldflags", arg_config("LDFLAGS", config["LDFLAGS"])).dup
    $INCFLAGS = "-I$(arch_hdrdir)"
    $INCFLAGS << " -I$(hdrdir)/ruby/backward" unless $extmk
    $INCFLAGS << " -I$(hdrdir) -I$(srcdir)"
    $DLDFLAGS = with_config("dldflags", arg_config("DLDFLAGS", config["DLDFLAGS"])).dup
    config_string("ADDITIONAL_DLDFLAGS") {|flags| $DLDFLAGS << " " << flags} unless $extmk
    $LIBEXT = config['LIBEXT'].dup
    $OBJEXT = config["OBJEXT"].dup
    $EXEEXT = config["EXEEXT"].dup
    $ASMEXT = config_string('ASMEXT', &:dup) || 'S'
    $LIBS = "#{config['LIBS']} #{config['DLDLIBS']}"
    $LIBRUBYARG = ""
    $LIBRUBYARG_STATIC = config['LIBRUBYARG_STATIC']
    $LIBRUBYARG_SHARED = config['LIBRUBYARG_SHARED']
    $DEFLIBPATH = [$extmk ? "$(topdir)" : "$(#{config["libdirname"] || "libdir"})"]
    $DEFLIBPATH.unshift(".")
    $LIBPATH = []
    $INSTALLFILES = []
    $NONINSTALLFILES = [/~\z/, /\A#.*#\z/, /\A\.#/, /\.bak\z/i, /\.orig\z/, /\.rej\z/, /\.l[ao]\z/, /\.o\z/]
    $VPATH = %w[$(srcdir) $(arch_hdrdir)/ruby $(hdrdir)/ruby]

    $objs = nil
    $srcs = nil
    $headers = []
    $libs = ""
    if $enable_shared or RbConfig.expand(config["LIBRUBY"].dup) != RbConfig.expand(config["LIBRUBY_A"].dup)
      $LIBRUBYARG = config['LIBRUBYARG']
    end

    $LOCAL_LIBS = ""

    $cleanfiles = config_string('CLEANFILES') {|s| Shellwords.shellwords(s)} || []
    $cleanfiles << "mkmf.log"
    $distcleanfiles = config_string('DISTCLEANFILES') {|s| Shellwords.shellwords(s)} || []
    $distcleandirs = config_string('DISTCLEANDIRS') {|s| Shellwords.shellwords(s)} || []

    $extout ||= nil
    $extout_prefix ||= nil

    $arg_config.clear
    $config_dirs.clear
    dir_config("opt")
  end

  FailedMessage = <<MESSAGE
Could not create Makefile due to some reason, probably lack of necessary
libraries and/or headers.  Check the mkmf.log file for more details.  You may
need configuration options.

Provided configuration options:
MESSAGE

  # Returns whether or not the Makefile was successfully generated. If not,
  # the script will abort with an error message.
  #
  # Internal use only.
  #
  def mkmf_failed(path)
    unless $makefile_created or File.exist?("Makefile")
      opts = $arg_config.collect {|t, n| "\t#{t}#{n ? "=#{n}" : ""}\n"}
      abort "*** #{path} failed ***\n" + FailedMessage + opts.join
    end
  end

  private

  def _libdir_basename
    @libdir_basename ||= config_string("libdir") {|name| name[/\A\$\(exec_prefix\)\/(.*)/, 1]} || "lib"
  end

  def MAIN_DOES_NOTHING(*refs)
    src = MAIN_DOES_NOTHING
    unless refs.empty?
      src = src.sub(/\{/) do
        $& +
          "\n  if (argc > 1000000) {\n" +
          refs.map {|n|"    int (* volatile #{n}p)(void)=(int (*)(void))&#{n};\n"}.join("") +
          refs.map {|n|"    printf(\"%d\", (*#{n}p)());\n"}.join("") +
          "  }\n"
      end
    end
    src
  end

  extend self
  init_mkmf

  $make = with_config("make-prog", ENV["MAKE"] || "make")
  make, = Shellwords.shellwords($make)
  $nmake = nil
  case
  when $mswin
    $nmake = ?m if /nmake/i =~ make
  end
  $ignore_error = " 2> #{File::NULL} || #{$mswin ? 'exit /b0' : 'true'}"

  RbConfig::CONFIG["srcdir"] = CONFIG["srcdir"] =
    $srcdir = arg_config("--srcdir", File.dirname($0))
  $configure_args["--topsrcdir"] ||= $srcdir
  if $curdir = arg_config("--curdir")
    RbConfig.expand(curdir = $curdir.dup)
  else
    curdir = $curdir = "."
  end
  unless File.expand_path(RbConfig::CONFIG["topdir"]) == File.expand_path(curdir)
    CONFIG["topdir"] = $curdir
    RbConfig::CONFIG["topdir"] = curdir
  end
  $configure_args["--topdir"] ||= $curdir
  $ruby = arg_config("--ruby", File.join(RbConfig::CONFIG["bindir"], CONFIG["ruby_install_name"]))

  RbConfig.expand(CONFIG["RUBY_SO_NAME"])

  # :startdoc:

  split = Shellwords.method(:shellwords).to_proc

  EXPORT_PREFIX = config_string('EXPORT_PREFIX') {|s| s.strip}

  hdr = ['#include "ruby.h"' "\n"]
  config_string('COMMON_MACROS') do |s|
    Shellwords.shellwords(s).each do |w|
      w, v = w.split(/=/, 2)
      hdr << "#ifndef #{w}"
      hdr << "#define #{[w, v].compact.join(" ")}"
      hdr << "#endif /* #{w} */"
    end
  end
  config_string('COMMON_HEADERS') do |s|
    Shellwords.shellwords(s).each {|w| hdr << "#include <#{w}>"}
  end

  ##
  # Common headers for Ruby C extensions

  COMMON_HEADERS = hdr.join("\n")

  ##
  # Common libraries for Ruby C extensions

  COMMON_LIBS = config_string('COMMON_LIBS', &split) || []

  ##
  # make compile rules

  COMPILE_RULES = config_string('COMPILE_RULES', &split) || %w[.%s.%s:]
  RULE_SUBST = config_string('RULE_SUBST')

  ##
  # Command which will compile C files in the generated Makefile

  COMPILE_C = config_string('COMPILE_C') || '$(CC) $(INCFLAGS) $(CPPFLAGS) $(CFLAGS) $(COUTFLAG)$@ -c $(CSRCFLAG)$<'

  ##
  # Command which will compile C++ files in the generated Makefile

  COMPILE_CXX = config_string('COMPILE_CXX') || '$(CXX) $(INCFLAGS) $(CPPFLAGS) $(CXXFLAGS) $(COUTFLAG)$@ -c $(CSRCFLAG)$<'

  ##
  # Command which will translate C files to assembler sources in the generated Makefile

  ASSEMBLE_C = config_string('ASSEMBLE_C') || COMPILE_C.sub(/(?<=\s)-c(?=\s)/, '-S')

  ##
  # Command which will translate C++ files to assembler sources in the generated Makefile

  ASSEMBLE_CXX = config_string('ASSEMBLE_CXX') || COMPILE_CXX.sub(/(?<=\s)-c(?=\s)/, '-S')

  ##
  # Command which will compile a program in order to test linking a library

  TRY_LINK = config_string('TRY_LINK') ||
    "$(CC) #{OUTFLAG}#{CONFTEST}#{$EXEEXT} $(INCFLAGS) $(CPPFLAGS) " \
    "$(CFLAGS) $(src) $(LIBPATH) $(LDFLAGS) $(ARCH_FLAG) $(LOCAL_LIBS) $(LIBS)"

  ##
  # Command which will link a shared library

  LINK_SO = (config_string('LINK_SO') || "").sub(/^$/) do
    if CONFIG["DLEXT"] == $OBJEXT
      "ld $(DLDFLAGS) -r -o $@ $(OBJS)\n"
    else
      "$(LDSHARED) #{OUTFLAG}$@ $(OBJS) " \
      "$(LIBPATH) $(DLDFLAGS) $(LOCAL_LIBS) $(LIBS)"
    end
  end

  ##
  # Argument which will add a library path to the linker

  LIBPATHFLAG = config_string('LIBPATHFLAG') || ' -L%s'
  RPATHFLAG = config_string('RPATHFLAG') || ''

  ##
  # Argument which will add a library to the linker

  LIBARG = config_string('LIBARG') || '-l%s'

  ##
  # A C main function which does no work

  MAIN_DOES_NOTHING = config_string('MAIN_DOES_NOTHING') || "int main(int argc, char **argv)\n{\n  return !!argv[argc];\n}"
  UNIVERSAL_INTS = config_string('UNIVERSAL_INTS') {|s| Shellwords.shellwords(s)} ||
    %w[int short long long\ long]

  sep = config_string('BUILD_FILE_SEPARATOR') {|s| ":/=#{s}" if s != "/"} || ""

  ##
  # Makefile rules that will clean the extension build directory

  CLEANINGS = "
clean-static::
clean-rb-default::
clean-rb::
clean-so::
clean: clean-so clean-static clean-rb-default clean-rb
\t\t-$(Q)$(RM_RF) $(CLEANLIBS#{sep}) $(CLEANOBJS#{sep}) $(CLEANFILES#{sep}) .*.time

distclean-rb-default::
distclean-rb::
distclean-so::
distclean-static::
distclean: clean distclean-so distclean-static distclean-rb-default distclean-rb
\t\t-$(Q)$(RM) Makefile $(RUBY_EXTCONF_H) #{CONFTEST}.* mkmf.log#{' exts.mk' if $extmk}
\t\t-$(Q)$(RM) core ruby$(EXEEXT) *~ $(DISTCLEANFILES#{sep})
\t\t-$(Q)$(RMDIRS) $(DISTCLEANDIRS#{sep})#{$ignore_error}

realclean: distclean
"

  @lang = Hash.new(self)

  def self.[](name)
    @lang.fetch(name)
  end

  def self.[]=(name, mod)
    @lang[name] = mod
  end

  self["C++"] = Module.new do
    include MakeMakefile
    extend self

    CONFTEST_CXX = "#{CONFTEST}.#{config_string('CXX_EXT') || CXX_EXT[0]}"

    TRY_LINK_CXX = config_string('TRY_LINK_CXX') ||
                   ((cmd = TRY_LINK.gsub(/\$\(C(?:C|(FLAGS))\)/, '$(CXX\1)')) != TRY_LINK && cmd) ||
                   "$(CXX) #{OUTFLAG}#{CONFTEST}#{$EXEEXT} $(INCFLAGS) $(CPPFLAGS) " \
                   "$(CXXFLAGS) $(src) $(LIBPATH) $(LDFLAGS) $(ARCH_FLAG) $(LOCAL_LIBS) $(LIBS)"

    def have_devel?
      unless defined? @have_devel
        @have_devel = true
        @have_devel = try_link(MAIN_DOES_NOTHING)
      end
      @have_devel
    end

    def conftest_source
      CONFTEST_CXX
    end

    def cc_command(opt="")
      conf = cc_config(opt)
      RbConfig::expand("$(CXX) #$INCFLAGS #$CPPFLAGS #$CXXFLAGS #$ARCH_FLAG #{opt} -c #{CONFTEST_CXX}",
                       conf)
    end

    def link_command(ldflags, *opts)
      conf = link_config(ldflags, *opts)
      RbConfig::expand(TRY_LINK_CXX.dup, conf)
    end
  end
end

# MakeMakefile::Global = #
m = Module.new {
  include(MakeMakefile)
  private(*MakeMakefile.public_instance_methods(false))
}
include m

if not $extmk and /\A(extconf|makefile).rb\z/ =~ File.basename($0)
  END {mkmf_failed($0)}
end
