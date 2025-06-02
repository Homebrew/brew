# encoding: ascii-8bit
# frozen-string-literal: false
#
# The module storing Ruby interpreter configurations on building.
#
# This file was created by mkconfig.rb when ruby was built.  It contains
# build information for ruby which is used e.g. by mkmf to build
# compatible native extensions.  Any changes made to this file will be
# lost the next time ruby is built.

module RbConfig
  RUBY_VERSION.start_with?("3.1.") or
    raise "ruby lib version (3.1.4) doesn't match executable version (#{RUBY_VERSION})"

  # Ruby installed directory.
  TOPDIR = File.dirname(__FILE__).chomp!("/lib/ruby/3.1.0/x86_64-linux")
  # DESTDIR on make install.
  DESTDIR = '' unless defined? DESTDIR
  # The hash configurations stored.
  CONFIG = {}
  CONFIG["DESTDIR"] = DESTDIR
  CONFIG["MAJOR"] = "3"
  CONFIG["MINOR"] = "1"
  CONFIG["TEENY"] = "4"
  CONFIG["PATCHLEVEL"] = "223"
  CONFIG["INSTALL"] = '/usr/bin/install -c'
  CONFIG["EXEEXT"] = ""
  CONFIG["prefix"] = (TOPDIR || DESTDIR + "/home/linuxbrew/.linuxbrew/Cellar/portable-ruby/3.1.4")
  CONFIG["ruby_install_name"] = "$(RUBY_BASE_NAME)"
  CONFIG["RUBY_INSTALL_NAME"] = "$(RUBY_BASE_NAME)"
  CONFIG["RUBY_SO_NAME"] = "$(RUBY_BASE_NAME)"
  CONFIG["exec"] = "exec"
  CONFIG["ruby_pc"] = "ruby-3.1.pc"
  CONFIG["CC_WRAPPER"] = ""
  CONFIG["PACKAGE"] = "ruby"
  CONFIG["BUILTIN_TRANSSRCS"] = " enc/trans/newline.c"
  CONFIG["MKMF_VERBOSE"] = "0"
  CONFIG["MANTYPE"] = "man"
  CONFIG["vendorarchhdrdir"] = "$(vendorhdrdir)/$(sitearch)"
  CONFIG["sitearchhdrdir"] = "$(sitehdrdir)/$(sitearch)"
  CONFIG["rubyarchhdrdir"] = "$(rubyhdrdir)/$(arch)"
  CONFIG["vendorhdrdir"] = "$(rubyhdrdir)/vendor_ruby"
  CONFIG["sitehdrdir"] = "$(rubyhdrdir)/site_ruby"
  CONFIG["rubyhdrdir"] = "$(includedir)/$(RUBY_VERSION_NAME)"
  CONFIG["RUBY_SEARCH_PATH"] = ""
  CONFIG["UNIVERSAL_INTS"] = ""
  CONFIG["UNIVERSAL_ARCHNAMES"] = ""
  CONFIG["configure_args"] = " '--prefix=/home/linuxbrew/.linuxbrew/Cellar/portable-ruby/3.1.4' '--enable-load-relative' '--with-static-linked-ext' '--without-ext=win32,win32ole' '--without-gmp' '--enable-libedit' '--disable-install-doc' '--disable-install-rdoc' '--disable-dependency-tracking' 'MJIT_CC=/usr/bin/gcc' '--with-libyaml-dir=/home/linuxbrew/.linuxbrew/opt/portable-libyaml' '--with-libedit-dir=/home/linuxbrew/.linuxbrew/opt/portable-libedit' '--with-libffi-dir=/home/linuxbrew/.linuxbrew/opt/portable-libffi' '--with-ncurses-dir=/home/linuxbrew/.linuxbrew/opt/portable-ncurses' '--with-zlib-dir=/home/linuxbrew/.linuxbrew/opt/portable-zlib' 'MKDIR_P=/bin/mkdir -p' 'cflags=-fPIC' 'cxxflags=-fPIC' 'CC=cc' 'CXX=c++'"
  CONFIG["CONFIGURE"] = "configure"
  CONFIG["vendorarchdir"] = "$(vendorlibdir)/$(sitearch)"
  CONFIG["vendorlibdir"] = "$(vendordir)/$(ruby_version)"
  CONFIG["vendordir"] = "$(rubylibprefix)/vendor_ruby"
  CONFIG["sitearchdir"] = "$(sitelibdir)/$(sitearch)"
  CONFIG["sitelibdir"] = "$(sitedir)/$(ruby_version)"
  CONFIG["sitedir"] = "$(rubylibprefix)/site_ruby"
  CONFIG["rubyarchdir"] = "$(rubylibdir)/$(arch)"
  CONFIG["rubylibdir"] = "$(rubylibprefix)/$(ruby_version)"
  CONFIG["ruby_version"] = "3.1.0"
  CONFIG["sitearch"] = "$(arch)"
  CONFIG["arch"] = "x86_64-linux"
  CONFIG["sitearchincludedir"] = "$(includedir)/$(sitearch)"
  CONFIG["archincludedir"] = "$(includedir)/$(arch)"
  CONFIG["sitearchlibdir"] = "$(libdir)/$(sitearch)"
  CONFIG["archlibdir"] = "$(libdir)/$(arch)"
  CONFIG["libdirname"] = "libdir"
  CONFIG["RUBY_EXEC_PREFIX"] = ""
  CONFIG["RUBY_LIB_VERSION"] = ""
  CONFIG["RUBY_LIB_VERSION_STYLE"] = "3\t/* full */"
  CONFIG["RI_BASE_NAME"] = "ri"
  CONFIG["ridir"] = "$(datarootdir)/$(RI_BASE_NAME)"
  CONFIG["rubysitearchprefix"] = "$(rubylibprefix)/$(sitearch)"
  CONFIG["rubyarchprefix"] = "$(rubylibprefix)/$(arch)"
  CONFIG["MAKEFILES"] = "Makefile GNUmakefile"
  CONFIG["PLATFORM_DIR"] = ""
  CONFIG["THREAD_MODEL"] = "pthread"
  CONFIG["SYMBOL_PREFIX"] = ""
  CONFIG["EXPORT_PREFIX"] = ""
  CONFIG["COMMON_HEADERS"] = ""
  CONFIG["COMMON_MACROS"] = ""
  CONFIG["COMMON_LIBS"] = ""
  CONFIG["MAINLIBS"] = "-lz -lpthread -lrt -lrt -lrt -ldl -lcrypt -lm "
  CONFIG["ENABLE_SHARED"] = "no"
  CONFIG["DLDSHARED"] = "$(CC) -shared"
  CONFIG["DLDLIBS"] = "-lc"
  CONFIG["SOLIBS"] = "$(MAINLIBS)"
  CONFIG["LIBRUBYARG_SHARED"] = "-Wl,-rpath,$(libdir) "
  CONFIG["LIBRUBYARG_STATIC"] = "-Wl,-rpath,$(libdir) -l$(RUBY_SO_NAME)-static $(MAINLIBS)"
  CONFIG["LIBRUBYARG"] = "$(LIBRUBYARG_STATIC)"
  CONFIG["LIBRUBY"] = "$(LIBRUBY_A)"
  CONFIG["LIBRUBY_ALIASES"] = "lib$(RUBY_SO_NAME).$(SOEXT)"
  CONFIG["LIBRUBY_SONAME"] = "lib$(RUBY_SO_NAME).$(SOEXT).$(RUBY_API_VERSION)"
  CONFIG["LIBRUBY_SO"] = "lib$(RUBY_SO_NAME).$(SOEXT).$(RUBY_PROGRAM_VERSION)"
  CONFIG["LIBRUBY_A"] = "lib$(RUBY_SO_NAME)-static.a"
  CONFIG["RUBYW_INSTALL_NAME"] = ""
  CONFIG["rubyw_install_name"] = ""
  CONFIG["EXTDLDFLAGS"] = ""
  CONFIG["EXTLDFLAGS"] = ""
  CONFIG["strict_warnflags"] = "-std=gnu99"
  CONFIG["warnflags"] = "-Wall -Wextra -Wdeprecated-declarations -Wduplicated-cond -Wimplicit-function-declaration -Wimplicit-int -Wmisleading-indentation -Wpointer-arith -Wwrite-strings -Wold-style-definition -Wimplicit-fallthrough=0 -Wmissing-noreturn -Wno-cast-function-type -Wno-constant-logical-operand -Wno-long-long -Wno-missing-field-initializers -Wno-overlength-strings -Wno-packed-bitfield-compat -Wno-parentheses-equality -Wno-self-assign -Wno-tautological-compare -Wno-unused-parameter -Wno-unused-value -Wsuggest-attribute=format -Wsuggest-attribute=noreturn -Wunused-variable -Wundef"
  CONFIG["debugflags"] = "-ggdb3"
  CONFIG["optflags"] = "-O3 -fno-fast-math"
  CONFIG["NULLCMD"] = ":"
  CONFIG["ENABLE_DEBUG_ENV"] = ""
  CONFIG["DLNOBJ"] = "dln.o"
  CONFIG["INSTALL_STATIC_LIBRARY"] = "yes"
  CONFIG["MJIT_SUPPORT"] = "yes"
  CONFIG["EXECUTABLE_EXTS"] = ""
  CONFIG["ARCHFILE"] = ""
  CONFIG["LIBRUBY_RELATIVE"] = "yes"
  CONFIG["EXTOUT"] = ".ext"
  CONFIG["PREP"] = "miniruby$(EXEEXT)"
  CONFIG["CROSS_COMPILING"] = "no"
  CONFIG["TEST_RUNNABLE"] = "yes"
  CONFIG["rubylibprefix"] = "$(libdir)/$(RUBY_BASE_NAME)"
  CONFIG["setup"] = "Setup"
  CONFIG["ENCSTATIC"] = "static"
  CONFIG["EXTSTATIC"] = "static"
  CONFIG["SOEXT"] = "so"
  CONFIG["TRY_LINK"] = ""
  CONFIG["PRELOADENV"] = "LD_PRELOAD"
  CONFIG["LIBPATHENV"] = "LD_LIBRARY_PATH"
  CONFIG["RPATHFLAG"] = " -Wl,-rpath,%1$-s"
  CONFIG["LIBPATHFLAG"] = " -L%1$-s"
  CONFIG["LINK_SO"] = ""
  CONFIG["ADDITIONAL_DLDFLAGS"] = ""
  CONFIG["ASMEXT"] = "S"
  CONFIG["LIBEXT"] = "a"
  CONFIG["DLEXT"] = "so"
  CONFIG["LDSHAREDXX"] = "$(CXX) -shared"
  CONFIG["LDSHARED"] = "$(CC) -shared"
  CONFIG["CCDLFLAGS"] = "-fPIC"
  CONFIG["STATIC"] = ""
  CONFIG["ARCH_FLAG"] = ""
  CONFIG["DLDFLAGS"] = "-Wl,--compress-debug-sections=zlib"
  CONFIG["ALLOCA"] = ""
  CONFIG["EGREP"] = "/usr/bin/grep -E"
  CONFIG["GREP"] = "/usr/bin/grep"
  CONFIG["dsymutil"] = ""
  CONFIG["codesign"] = ""
  CONFIG["cleanlibs"] = ""
  CONFIG["POSTLINK"] = ":"
  CONFIG["WERRORFLAG"] = "-Werror"
  CONFIG["CHDIR"] = "cd -P"
  CONFIG["RMALL"] = "rm -fr"
  CONFIG["RMDIRS"] = "rmdir --ignore-fail-on-non-empty -p"
  CONFIG["RMDIR"] = "rmdir --ignore-fail-on-non-empty"
  CONFIG["CP"] = "cp"
  CONFIG["RM"] = "rm -f"
  CONFIG["PKG_CONFIG"] = "pkg-config"
  CONFIG["DOXYGEN"] = ""
  CONFIG["DOT"] = ""
  CONFIG["MAKEDIRS"] = "/bin/mkdir -p"
  CONFIG["MKDIR_P"] = "/bin/mkdir -p"
  CONFIG["INSTALL_DATA"] = "$(INSTALL) -m 644"
  CONFIG["INSTALL_SCRIPT"] = "$(INSTALL)"
  CONFIG["INSTALL_PROGRAM"] = "$(INSTALL)"
  CONFIG["SET_MAKE"] = ""
  CONFIG["LN_S"] = "ln -s"
  CONFIG["DLLWRAP"] = ""
  CONFIG["WINDRES"] = ""
  CONFIG["ASFLAGS"] = ""
  CONFIG["ARFLAGS"] = "rcD "
  CONFIG["try_header"] = ""
  CONFIG["CC_VERSION_MESSAGE"] = "cc (Ubuntu 11.4.0-1ubuntu1~22.04) 11.4.0\nCopyright (C) 2021 Free Software Foundation, Inc.\nThis is free software; see the source for copying conditions.  There is NO\nwarranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE."
  CONFIG["CC_VERSION"] = "$(CC) --version"
  CONFIG["MJIT_CC"] = "/usr/bin/gcc"
  CONFIG["CSRCFLAG"] = ""
  CONFIG["COUTFLAG"] = "-o "
  CONFIG["OUTFLAG"] = "-o "
  CONFIG["CPPOUTFILE"] = "-o conftest.i"
  CONFIG["GNU_LD"] = "yes"
  CONFIG["GCC"] = "yes"
  CONFIG["CPP"] = "$(CC) -E"
  CONFIG["CXXFLAGS"] = "$(cxxflags)"
  CONFIG["OBJEXT"] = "o"
  CONFIG["CPPFLAGS"] = " $(DEFS) $(cppflags)"
  CONFIG["LDFLAGS"] = "-L. -fstack-protector-strong -rdynamic -Wl,-export-dynamic"
  CONFIG["CFLAGS"] = "$(cflags)"
  CONFIG["STRIP"] = "strip -S -x"
  CONFIG["RANLIB"] = "gcc-ranlib-11"
  CONFIG["OBJDUMP"] = "objdump"
  CONFIG["OBJCOPY"] = ":"
  CONFIG["NM"] = "gcc-nm-11"
  CONFIG["LD"] = "ld"
  CONFIG["CXX"] = "c++"
  CONFIG["AS"] = "as"
  CONFIG["AR"] = "gcc-ar-11"
  CONFIG["CC"] = "cc"
  CONFIG["target_os"] = "linux"
  CONFIG["target_vendor"] = "pc"
  CONFIG["target_cpu"] = "x86_64"
  CONFIG["target"] = "x86_64-pc-linux-gnu"
  CONFIG["host_os"] = "linux"
  CONFIG["host_vendor"] = "pc"
  CONFIG["host_cpu"] = "x86_64"
  CONFIG["host"] = "x86_64-pc-linux-gnu"
  CONFIG["build_os"] = "linux-gnu"
  CONFIG["build_vendor"] = "pc"
  CONFIG["build_cpu"] = "x86_64"
  CONFIG["build"] = "x86_64-pc-linux-gnu"
  CONFIG["RUBY_VERSION_NAME"] = "$(RUBY_BASE_NAME)-$(ruby_version)"
  CONFIG["RUBYW_BASE_NAME"] = "rubyw"
  CONFIG["RUBY_BASE_NAME"] = "ruby"
  CONFIG["RUBY_PROGRAM_VERSION"] = "$(MAJOR).$(MINOR).$(TEENY)"
  CONFIG["RUBY_API_VERSION"] = "$(MAJOR).$(MINOR)"
  CONFIG["HAVE_GIT"] = "yes"
  CONFIG["GIT"] = "git"
  CONFIG["cxxflags"] = "-fPIC"
  CONFIG["cppflags"] = ""
  CONFIG["cflags"] = "-fPIC $(optflags) $(debugflags) $(warnflags)"
  CONFIG["target_alias"] = ""
  CONFIG["host_alias"] = ""
  CONFIG["build_alias"] = ""
  CONFIG["LIBS"] = "-lm "
  CONFIG["ECHO_T"] = ""
  CONFIG["ECHO_N"] = "-n"
  CONFIG["ECHO_C"] = ""
  CONFIG["DEFS"] = ""
  CONFIG["mandir"] = "$(datarootdir)/man"
  CONFIG["localedir"] = "$(datarootdir)/locale"
  CONFIG["libdir"] = "$(exec_prefix)/lib"
  CONFIG["psdir"] = "$(docdir)"
  CONFIG["pdfdir"] = "$(docdir)"
  CONFIG["dvidir"] = "$(docdir)"
  CONFIG["htmldir"] = "$(docdir)"
  CONFIG["infodir"] = "$(datarootdir)/info"
  CONFIG["docdir"] = "$(datarootdir)/doc/$(PACKAGE)"
  CONFIG["oldincludedir"] = "/usr/include"
  CONFIG["includedir"] = "$(prefix)/include"
  CONFIG["runstatedir"] = "$(localstatedir)/run"
  CONFIG["localstatedir"] = "$(prefix)/var"
  CONFIG["sharedstatedir"] = "$(prefix)/com"
  CONFIG["sysconfdir"] = "$(prefix)/etc"
  CONFIG["datadir"] = "$(datarootdir)"
  CONFIG["datarootdir"] = "$(prefix)/share"
  CONFIG["libexecdir"] = "$(exec_prefix)/libexec"
  CONFIG["sbindir"] = "$(exec_prefix)/sbin"
  CONFIG["bindir"] = "$(exec_prefix)/bin"
  CONFIG["exec_prefix"] = "$(prefix)"
  CONFIG["PACKAGE_URL"] = ""
  CONFIG["PACKAGE_BUGREPORT"] = ""
  CONFIG["PACKAGE_STRING"] = ""
  CONFIG["PACKAGE_VERSION"] = ""
  CONFIG["PACKAGE_TARNAME"] = ""
  CONFIG["PACKAGE_NAME"] = ""
  CONFIG["PATH_SEPARATOR"] = ":"
  CONFIG["SHELL"] = "/bin/bash"
  CONFIG["UNICODE_VERSION"] = "13.0.0"
  CONFIG["UNICODE_EMOJI_VERSION"] = "13.1"
  CONFIG["platform"] = "$(arch)"
  CONFIG["archdir"] = "$(rubyarchdir)"
  CONFIG["topdir"] = File.dirname(__FILE__)
  # Almost same with CONFIG. MAKEFILE_CONFIG has other variable
  # reference like below.
  #
  #   MAKEFILE_CONFIG["bindir"] = "$(exec_prefix)/bin"
  #
  # The values of this constant is used for creating Makefile.
  #
  #   require 'rbconfig'
  #
  #   print <<-END_OF_MAKEFILE
  #   prefix = #{RbConfig::MAKEFILE_CONFIG['prefix']}
  #   exec_prefix = #{RbConfig::MAKEFILE_CONFIG['exec_prefix']}
  #   bindir = #{RbConfig::MAKEFILE_CONFIG['bindir']}
  #   END_OF_MAKEFILE
  #
  #   => prefix = /usr/local
  #      exec_prefix = $(prefix)
  #      bindir = $(exec_prefix)/bin  MAKEFILE_CONFIG = {}
  #
  # RbConfig.expand is used for resolving references like above in rbconfig.
  #
  #   require 'rbconfig'
  #   p RbConfig.expand(RbConfig::MAKEFILE_CONFIG["bindir"])
  #   # => "/usr/local/bin"
  MAKEFILE_CONFIG = {}
  CONFIG.each{|k,v| MAKEFILE_CONFIG[k] = v.dup}

  # call-seq:
  #
  #   RbConfig.expand(val)         -> string
  #   RbConfig.expand(val, config) -> string
  #
  # expands variable with given +val+ value.
  #
  #   RbConfig.expand("$(bindir)") # => /home/foobar/all-ruby/ruby19x/bin
  def RbConfig::expand(val, config = CONFIG)
    newval = val.gsub(/\$\$|\$\(([^()]+)\)|\$\{([^{}]+)\}/) {
      var = $&
      if !(v = $1 || $2)
	'$'
      elsif key = config[v = v[/\A[^:]+(?=(?::(.*?)=(.*))?\z)/]]
	pat, sub = $1, $2
	config[v] = false
	config[v] = RbConfig::expand(key, config)
	key = key.gsub(/#{Regexp.quote(pat)}(?=\s|\z)/n) {sub} if pat
	key
      else
	var
      end
    }
    val.replace(newval) unless newval == val
    val
  end
  CONFIG.each_value do |val|
    RbConfig::expand(val)
  end

  # :nodoc:
  # call-seq:
  #
  #   RbConfig.fire_update!(key, val)               -> array
  #   RbConfig.fire_update!(key, val, mkconf, conf) -> array
  #
  # updates +key+ in +mkconf+ with +val+, and all values depending on
  # the +key+ in +mkconf+.
  #
  #   RbConfig::MAKEFILE_CONFIG.values_at("CC", "LDSHARED") # => ["gcc", "$(CC) -shared"]
  #   RbConfig::CONFIG.values_at("CC", "LDSHARED")          # => ["gcc", "gcc -shared"]
  #   RbConfig.fire_update!("CC", "gcc-8")                  # => ["CC", "LDSHARED"]
  #   RbConfig::MAKEFILE_CONFIG.values_at("CC", "LDSHARED") # => ["gcc-8", "$(CC) -shared"]
  #   RbConfig::CONFIG.values_at("CC", "LDSHARED")          # => ["gcc-8", "gcc-8 -shared"]
  #
  # returns updated keys list, or +nil+ if nothing changed.
  def RbConfig.fire_update!(key, val, mkconf = MAKEFILE_CONFIG, conf = CONFIG)
    return if mkconf[key] == val
    mkconf[key] = val
    keys = [key]
    deps = []
    begin
      re = Regexp.new("\\$\\((?:%1$s)\\)|\\$\\{(?:%1$s)\\}" % keys.join('|'))
      deps |= keys
      keys.clear
      mkconf.each {|k,v| keys << k if re =~ v}
    end until keys.empty?
    deps.each {|k| conf[k] = mkconf[k].dup}
    deps.each {|k| expand(conf[k])}
    deps
  end

  # call-seq:
  #
  #   RbConfig.ruby -> path
  #
  # returns the absolute pathname of the ruby command.
  def RbConfig.ruby
    File.join(
      RbConfig::CONFIG["bindir"],
      RbConfig::CONFIG["ruby_install_name"] + RbConfig::CONFIG["EXEEXT"]
    )
  end
end
CROSS_COMPILING = nil unless defined? CROSS_COMPILING
