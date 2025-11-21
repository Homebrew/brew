#!/bin/bash
# vim: ft=ruby
# Make sure this shim uses the same Ruby interpreter that is used by Homebrew.
if [[ -z "${HOMEBREW_RUBY_PATH}" ]]
then
  echo "${0##*/}: The build tool has reset ENV; --env=std required." >&2
  exit 1
fi
unset HOMEBREW_LD_LIBRARY_PATH
if [[ -n "${LD_LIBRARY_PATH+set}" ]]
then
  export HOMEBREW_LD_LIBRARY_PATH="${LD_LIBRARY_PATH}"
fi
unset LD_LIBRARY_PATH
unset RUBYLIB
exec "${HOMEBREW_RUBY_PATH}" --enable-frozen-string-literal --disable=gems,did_you_mean,rubyopt -x "$0" "$@"
#!/usr/bin/env ruby -W0

require "pathname"
require "set"
require "English"

def mac?
  RUBY_PLATFORM[/darwin/]
end

def linux?
  RUBY_PLATFORM[/linux/]
end

class Cmd
  CXX_REGEX = /(?:c|g|clang)\+\+/.freeze

  attr_reader :config, :prefix, :cellar, :opt, :cachedir, :tmpdir, :sysroot, :deps
  attr_reader :archflags, :optflags, :keg_regex, :formula_prefix, :formula_buildpath

  def initialize(arg0, args)
    @arg0 = arg0
    split_args = split_args_at_double_dash(args)
    @args = split_args[0].freeze
    @positional_args = split_args[1].freeze
    @config = ENV.fetch("HOMEBREW_CCCFG", "")
    @prefix = ENV["HOMEBREW_PREFIX"]
    @cellar = ENV["HOMEBREW_CELLAR"]
    @cachedir = ENV["HOMEBREW_CACHE"]
    @opt = ENV["HOMEBREW_OPT"]
    @tmpdir = ENV["HOMEBREW_TEMP"]
    @sysroot = ENV["HOMEBREW_SDKROOT"]
    @archflags = ENV.fetch("HOMEBREW_ARCHFLAGS", "").split
    @optflags = ENV.fetch("HOMEBREW_OPTFLAGS", "").split
    @deps = Set.new(ENV.fetch("HOMEBREW_DEPENDENCIES", "").split(","))
    @formula_prefix = ENV["HOMEBREW_FORMULA_PREFIX"]
    @formula_buildpath = ENV["HOMEBREW_FORMULA_BUILDPATH"]
    # matches opt or Cellar prefix and formula name
    @keg_regex = %r{(#{Regexp.escape(opt)}|#{Regexp.escape(cellar)})/([\w+-.@]+)}
  end

  def split_args_at_double_dash(args)
    double_dash_index = args.find_index("--")
    if double_dash_index
      [args[...double_dash_index], args[double_dash_index..]]
    else
      [args, []]
    end
  end

  def mode
    if @arg0 == "cpp"
      :cpp
    elsif ["ld", "ld.gold", "gold"].include? @arg0
      :ld
    elsif @args.include? "-c"
      if CXX_REGEX.match?(@arg0)
        :cxx
      else
        :cc
      end
    elsif @args.include?("-xc++-header") || @args.each_cons(2).include?(["-x", "c++-header"])
      :cxx
    elsif @args.include? "-E"
      :ccE
    elsif CXX_REGEX.match?(@arg0)
      :cxxld
    else
      :ccld
    end
  end

  def tool
    @tool ||= case @arg0
    when "ld" then "ld"
    when "gold", "ld.gold" then "ld.gold"
    when "cpp" then "cpp"
    when /llvm_(clang(\+\+)?)/
      "#{ENV["HOMEBREW_PREFIX"]}/opt/llvm/bin/#{Regexp.last_match(1)}"
    when /\w\+\+(-\d+(\.\d)?)?$/
      case ENV["HOMEBREW_CC"]
      when "swift_clang"
        "#{ENV["HOMEBREW_PREFIX"]}/opt/swift/libexec/bin/clang++"
      when /clang/
        "clang++"
      when /(g)?cc(-\d+(\.\d)?)?$/
        "g++#{Regexp.last_match(2)}"
      end
    else
      # Note that this is a universal fallback, so that we'll always invoke
      # HOMEBREW_CC regardless of what name under which the tool was invoked.
      if ENV["HOMEBREW_CC"] == "llvm_clang"
        "#{ENV["HOMEBREW_PREFIX"]}/opt/llvm/bin/clang"
      elsif ENV["HOMEBREW_CC"] == "swift_clang"
        "#{ENV["HOMEBREW_PREFIX"]}/opt/swift/libexec/bin/clang"
      else
        ENV["HOMEBREW_CC"]
      end
    end
  end

  def args
    if @args.length == 1 && @args[0] == "-v"
      # Don't add linker arguments if -v passed as sole option. This stops gcc
      # -v with no other arguments from outputting a linker error. Some
      # software uses gcc -v (wrongly) to sniff the GCC version.
      return @args.dup
    end

    args = if !refurbish_args? || mode == :ld || configure?
      @args.dup
    else
      refurbished_args
    end

    if sysroot
      if tool == "ld"
        args << "-syslibroot" << sysroot
      else
        args << "-isysroot#{sysroot}" << "--sysroot=#{sysroot}"
      end
    end

    optional_args = case mode
    when :ccld
      cflags + args + cppflags + ldflags
    when :cxxld
      cxxflags + args + cppflags + ldflags
    when :cc
      cflags + args + cppflags
    when :cxx
      cxxflags + args + cppflags
    when :ccE
      args + cppflags
    when :cpp
      args + cppflags
    when :ld
      ldflags + args
    end

    optional_args + @positional_args
  end

  def refurbished_args
    @lset = Set.new(library_paths + system_library_paths)
    @iset = Set.new(isystem_paths + include_paths)

    args = []
    enum = @args.each

    loop do
      case arg = enum.next
      when "-arch"
        if permit_arch_flags?
          args << arg << enum.next
        else
          enum.next
        end
      when "-m32", "-m64"
        args << arg if permit_arch_flags?
      when /^-Xarch_/
        refurbished = refurbish_arg(enum.next, enum)
        unless refurbished.empty?
          args << arg
          args += refurbished
        end
      else
        args += refurbish_arg(arg, enum)
      end
    end

    args
  end

  def refurbish_arg(arg, enum)
    args = []

    case arg
    when /^-g\d?$/, /^-gstabs\d+/, "-gstabs+", /^-ggdb\d?/,
      /^-mtune=.+/, /^-mcpu=.+/, /^-O[0-9zs]?$/,
      "-fast", "-no-cpp-precomp", "-pedantic",
      "-pedantic-errors", "-Wno-long-double",
      "-Wno-unused-but-set-variable"
    when /^-march=.+/
      args << arg if runtime_cpu_detection?
    when "-fopenmp", "-lgomp", "-mno-fused-madd", "-fforce-addr", "-fno-defer-pop",
      "-mno-dynamic-no-pic", "-fearly-inlining", /^-f(?:no-)?inline-functions-called-once/,
      /^-finline-limit/, /^-f(?:no-)?check-new/, "-fno-delete-null-pointer-checks",
      "-fcaller-saves", "-fthread-jumps", "-fno-reorder-blocks", "-fcse-skip-blocks",
      "-frerun-cse-after-loop", "-frerun-loop-opt", "-fcse-follow-jumps",
      "-fno-regmove", "-fno-for-scope", "-fno-tree-pre", "-fno-tree-dominator-opts",
      "-fuse-linker-plugin", "-frounding-math"
      # clang doesn't support these flags
      args << arg unless tool =~ /^clang/
    when "-Xpreprocessor", "-Xclang"
      # used for -Xpreprocessor -fopenmp
      args << arg << enum.next
    when /-mmacosx-version-min=(\d+)\.(\d+)/
      if Regexp.last_match(1) == "10" && Regexp.last_match(2).to_i < 9
        arg = "-mmacosx-version-min=10.9"
      end
      args << arg
    when "--fast-math"
      arg = "-ffast-math" if /^clang/.match?(tool)
      args << arg
    when "-Wno-deprecated-register"
      # older gccs don't support these flags
      args << arg unless tool =~ /^g..-4.[02]/
    when /^-Wl,-z,defs/
      # -Wl,-undefined,error is already the default
    when /^-W[alp],/, /^-Wno-/, "-Werror=implicit-function-declaration"
      args << arg
    when /^-W.*/
      # prune warnings
    when "-macosx_version_min", "-dylib_install_name"
      args << "-Wl,#{arg},#{enum.next}"
    when "-multiply_definedsuppress"
      args << "-Wl,-multiply_defined,suppress"
    when "-undefineddynamic_lookup"
      args << "-Wl,-undefined,dynamic_lookup"
    when /^-isysroot=/, /^--sysroot=/
      if mac?
        sdk = arg.split("=", 2).last
        # We set the sysroot for macOS SDKs
        args << arg unless sdk.downcase.include? "osx"
      else
        args << arg
      end
    when /^-isysroot(.+)?/, /^--sysroot(.+)?/
      # Support both "-isysrootfoo" and "-isysroot foo" (two arguments)
      sdk = chuzzle(Regexp.last_match(1))
      if mac?
        sdk ||= enum.next
        # We set the sysroot for macOS SDKs
        args << "-isysroot#{sdk}" if !sdk.downcase.include?("osx") && !sdk.empty?
      else
        args << arg
        args << enum.next unless sdk
      end
    when "-dylib"
      args << "-Wl,#{arg}"
    when /^-I(.+)?/
      # Support both "-Ifoo" (one argument) and "-I foo" (two arguments)
      val  = chuzzle(Regexp.last_match(1)) || enum.next
      path = canonical_path(val)
      args << "-I#{val}" if keep?(path) && @iset.add?(path)
    when /^-L(.+)?/
      val  = chuzzle(Regexp.last_match(1)) || enum.next
      path = canonical_path(val)
      args << "-L#{val}" if keep?(path) && @lset.add?(path)
    else
      args << arg
    end

    args
  end

  def keep?(path)
    # Allow references to self
    if formula_prefix && path.start_with?("#{formula_prefix}/")
      true
    # first two paths: reject references to Cellar or opt paths
    # for unspecified dependencies
    elsif path.start_with?(cellar, opt)
      dep = path[keg_regex, 2]
      dep && @deps.include?(dep)
    elsif path.start_with?(prefix, cachedir, tmpdir)
      true
    elsif path.start_with?("/opt/local", "/opt/boxen/homebrew", "/opt/X11", "/sw", "/usr/X11")
      # ignore MacPorts, Boxen's Homebrew, X11, fink
      false
    elsif prefix != "/usr/local" && path.start_with?("/usr/local")
      # ignore things in /usr/local if Homebrew is in another prefix;
      # on macOS, this probably means that the user is on ARM and has an Intel
      # Homebrew in /usr/local
      false
    elsif mac?
      true
    else
      false
    end
  end

  def cflags
    args = []

    return args if !refurbish_args? && !configure?

    args << "-w" unless configure?
    args << "-#{ENV["HOMEBREW_OPTIMIZATION_LEVEL"]}"
    optflags.each do |optflag|
      flag = optflag.split("=").first
      # For runtime CPU detection builds, pass our optimisation flag whenever the build hasn't provided its own.
      args << optflag if !runtime_cpu_detection? || @args.none? { |arg| arg.start_with?(flag) }
    end
    args.concat(archflags)
    args << "-std=#{@arg0}" if /c[89]9/.match?(@arg0)
    args << "-g" if debug_symbols?
    args
  end

  def cxxflags
    args = cflags
    args << "-std=c++11" if cxx11?
    args << "-stdlib=libc++" if libcxx?
    args << "-stdlib=libstdc++" if libstdcxx?
    if ENV["HOMEBREW_CC"] == "llvm_clang" && mac?
      args << "-I#{ENV["HOMEBREW_LIBRARY"]}/Homebrew/shims/mac/shared/include/llvm"
    end
    args
  end

  def cppflags
    args = []
    args += path_flags("-isystem", isystem_paths) + path_flags("-I", include_paths)
    # Add -nostdinc when building against versioned glibc to avoid mixing system and brewed glibc headers.
    args << "-nostdinc" if @deps.any? { |dep| dep.match?(/^glibc@.+$/) }
    # Ideally this would be -ffile-prefix-map, but that requires a minimum of GCC 8, LLVM Clang 10 or Apple Clang 12
    # and detecting the version dynamically based on what `HOMEBREW_CC` may have been rewritten to point to is awkward
    args << "-fdebug-prefix-map=#{formula_buildpath}=." if formula_buildpath && !debug_symbols?
    args << "-mbranch-protection=standard" if branch_protection?
    args
  end

  def ldflags_mac(args)
    case mode
    when :ld
      args << "-headerpad_max_install_names"
      args << "-no_weak_imports" if no_weak_imports?
      args << "-no_fixup_chains" if no_fixup_chains?
      args << "-oso_prefix" << formula_buildpath if oso_prefix? && formula_buildpath
      args << "-ld_classic" if ld_classic?
    when :ccld, :cxxld
      args << "-Wl,-headerpad_max_install_names"
      args << "-Wl,-no_weak_imports" if no_weak_imports?
      args << "-Wl,-no_fixup_chains" if no_fixup_chains?
      args << "-Wl,-oso_prefix,#{formula_buildpath}" if oso_prefix? && formula_buildpath
      args << "-Wl,-ld_classic" if ld_classic?
    end
    args
  end

  def ldflags_linux(args)
    versioned_glibc_dep = @deps.find { |dep| dep.match?(/^glibc@.+$/) }
    unless mode == :ld
      wl = "-Wl,"
      if versioned_glibc_dep
        args << "-B#{@opt}/#{versioned_glibc_dep}/lib"
      else
        args << "-B#{@opt}/glibc/lib"
      end
    end
    args += rpath_flags("#{wl}-rpath=", rpath_paths)
    args += ["#{wl}--dynamic-linker=#{dynamic_linker_path}"] if dynamic_linker_path
    # Use -rpath-link to make sure linker uses brew glibc rather than the system glibc for indirect
    # dependencies because -L will only handle direct dependencies.
    if versioned_glibc_dep
      args << "#{wl}-rpath-link=#{@opt}/#{versioned_glibc_dep}/lib"
    else
      args << "#{wl}-rpath-link=#{@opt}/glibc/lib"
    end
    args
  end

  def ldflags
    args = path_flags("-L", library_paths)
    if mac?
      ldflags_mac(args)
    elsif linux?
      ldflags_linux(args)
    else
      args
    end
  end

  def isystem_paths
    path_split("HOMEBREW_ISYSTEM_PATHS")
  end

  def include_paths
    path_split("HOMEBREW_INCLUDE_PATHS")
  end

  def library_paths
    path_split("HOMEBREW_LIBRARY_PATHS")
  end

  def rpath_paths
    path_split("HOMEBREW_RPATH_PATHS")
  end

  def dynamic_linker_path
    chuzzle(ENV["HOMEBREW_DYNAMIC_LINKER"])
  end

  def system_library_paths
    paths = [canonical_path("#{sysroot}/usr/lib")]
    paths << "/usr/local/lib" if !sysroot && !ENV["SDKROOT"]
    paths
  end

  def configure?
    # configure scripts generated with autoconf 2.61 or later export as_nl
    ENV.key? "as_nl"
  end

  def refurbish_args?
    config.include?("O")
  end

  def cxx11?
    config.include?("x")
  end

  def libcxx?
    config.include?("g")
  end

  def libstdcxx?
    config.include?("h")
  end

  def permit_arch_flags?
    config.include?("K")
  end

  def runtime_cpu_detection?
    config.include?("d")
  end

  def no_weak_imports?
    config.include?("w")
  end

  def debug_symbols?
    config.include?("D")
  end

  def branch_protection?
    config.include?("b")
  end

  def linker_flags
    @args.select { |arg| arg.start_with?("-Wl,") }
         .flat_map { |arg| arg.delete_prefix("-Wl,").split(",") }
  end

  def no_fixup_chains?
    return false unless config.include?("f")
    return false unless calls_ld?
    return true if @args.each_cons(2).include?(["-undefined", "dynamic_lookup"])
    return true if linker_flags.each_cons(2).include?(["-undefined", "dynamic_lookup"])

    # The next flag would produce an error, but we fix it in `refurbish_arg`.
    @args.include?("-undefineddynamic_lookup")
  end

  def oso_prefix?
    config.include?("o") && !configure? && !debug_symbols?
  end

  def ld_classic?
    return false unless config.include?("c")
    return false unless calls_ld?

    @args.include?("-dead_strip_dylibs") || linker_flags.include?("-dead_strip_dylibs")
  end

  def calls_ld?
    return true if mode == :ld
    return false unless [:ccld, :cxxld].include?(mode)

    fuse_ld_flags = @args.find_all { |arg| arg.match?(/^-fuse-ld=/) }
    return true if fuse_ld_flags.empty?

    fuse_ld_flag = fuse_ld_flags.last.strip
    fuse_ld_arg = fuse_ld_flag.split("=", 2).last

    (fuse_ld_arg == "ld") || fuse_ld_arg.end_with?("/usr/bin/ld")
  end

  def canonical_path(path)
    path = Pathname.new(path)
    path = path.realpath if path.exist?
    path.to_s
  end

  def path_flags(prefix, paths)
    paths = paths.uniq.select { |path| File.directory?(path) }
    paths.map! { |path| prefix + path }
  end

  # Unlike {path_flags}, do not prune non-existent directories.
  # `formula.lib` for example does not yet exist, but should not be pruned.
  def rpath_flags(prefix, paths)
    paths.uniq.map { |path| prefix + path }
  end

  def path_split(key)
    ENV.fetch(key, "").split(File::PATH_SEPARATOR)
  end

  def chuzzle(val)
    return val if val.nil?

    val = val.chomp
    return val unless val.empty?
  end
end

def log(basename, argv, tool, args)
  return unless ENV.key?("HOMEBREW_CC_LOG_PATH")

  log_filename = "#{ENV["HOMEBREW_CC_LOG_PATH"].delete_suffix(".log")}.cc.log"
  adds = args - argv
  dels = argv - args

  s = +""
  s << "#{basename} called with: #{argv.join(" ")}\n"
  s << "superenv removed:  #{dels.join(" ")}\n" unless dels.empty?
  s << "superenv added:    #{adds.join(" ")}\n" unless adds.empty?
  s << "superenv executed: #{tool} #{args.join(" ")}\n\n"
  File.open(log_filename, "a+") { |f| f.write(s) }
end

def remove_superbin_from_path(paths)
  superbin = Pathname.new(__FILE__).dirname.realpath
  paths.reject do |x|
    path = Pathname.new(x)
    path.directory? && path.realpath == superbin
  end
end

if __FILE__ == $PROGRAM_NAME
  ##################################################################### sanity

  if (cc = ENV["HOMEBREW_CC"]).nil? || cc.empty? || cc == "cc"
    # those values are not allowed
    ENV["HOMEBREW_CC"] = "clang"
  end

  ENV["LD_LIBRARY_PATH"] = ENV["HOMEBREW_LD_LIBRARY_PATH"]

  ####################################################################### main

  dirname, basename = File.split($PROGRAM_NAME)

  cmd = Cmd.new(basename, ARGV)
  tool = cmd.tool
  args = cmd.args

  log(basename, ARGV, tool, args)

  args << { close_others: false }
  if mac?
    exec "#{dirname}/xcrun", tool, *args
  else
    paths = ENV["PATH"].split(":")
    paths = remove_superbin_from_path(paths)
    paths.unshift "#{ENV["HOMEBREW_PREFIX"]}/bin"
    ENV["PATH"] = paths.join(":")
    exec tool, *args
  end
end
