# typed: true
# frozen_string_literal: true

require "compilers"
require "development_tools"

# Homebrew extends Ruby's `ENV` to make our code more readable.
# Implemented in {SharedEnvExtension} and either {Superenv} or
# {Stdenv} (depending on the build mode).
# @see Superenv
# @see Stdenv
# @see https://www.rubydoc.info/stdlib/Env Ruby's ENV API
module SharedEnvExtension
  include CompilerConstants

  CC_FLAG_VARS = %w[CFLAGS CXXFLAGS OBJCFLAGS OBJCXXFLAGS].freeze
  private_constant :CC_FLAG_VARS

  FC_FLAG_VARS = %w[FCFLAGS FFLAGS].freeze
  private_constant :FC_FLAG_VARS

  SANITIZED_VARS = %w[
    CDPATH CLICOLOR_FORCE
    CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH
    CC CXX OBJC OBJCXX CPP MAKE LD LDSHARED
    CFLAGS CXXFLAGS OBJCFLAGS OBJCXXFLAGS LDFLAGS CPPFLAGS
    MACOSX_DEPLOYMENT_TARGET SDKROOT DEVELOPER_DIR
    CMAKE_PREFIX_PATH CMAKE_INCLUDE_PATH CMAKE_FRAMEWORK_PATH
    GOBIN GOPATH GOROOT PERL_MB_OPT PERL_MM_OPT
    LIBRARY_PATH LD_LIBRARY_PATH LD_PRELOAD LD_RUN_PATH
    RUSTFLAGS
  ].freeze
  private_constant :SANITIZED_VARS

  sig {
    params(
      formula:         T.nilable(Formula),
      cc:              T.nilable(String),
      build_bottle:    T.nilable(T::Boolean),
      bottle_arch:     T.nilable(String),
      testing_formula: T::Boolean,
      debug_symbols:   T.nilable(T::Boolean),
    ).void
  }
  def setup_build_environment(formula: nil, cc: nil, build_bottle: false, bottle_arch: nil, testing_formula: false,
                              debug_symbols: false)
    @formula = formula
    @cc = cc
    @build_bottle = build_bottle
    @bottle_arch = bottle_arch
    @debug_symbols = debug_symbols
    reset
  end
  private :setup_build_environment
  alias generic_shared_setup_build_environment setup_build_environment

  sig { void }
  def reset
    SANITIZED_VARS.each { |k| delete(k) }
  end
  private :reset

  sig { returns(T::Hash[String, String]) }
  def remove_cc_etc
    keys = %w[CC CXX OBJC OBJCXX LD CPP CFLAGS CXXFLAGS OBJCFLAGS OBJCXXFLAGS LDFLAGS CPPFLAGS]
    keys.to_h { |key| [key, delete(key)] }
  end

  sig { params(newflags: String).void }
  def append_to_cflags(newflags)
    append(CC_FLAG_VARS, newflags)
  end

  sig { params(val: T.any(Regexp, String)).void }
  def remove_from_cflags(val)
    remove CC_FLAG_VARS, val
  end

  sig { params(value: String).void }
  def append_to_cccfg(value)
    append("HOMEBREW_CCCFG", value, "")
  end

  sig { params(keys: T.any(String, T::Array[String]), value: T.untyped, separator: String).void }
  def append(keys, value, separator = " ")
    value = value.to_s
    Array(keys).each do |key|
      old_value = self[key]
      self[key] = if old_value.blank?
        value
      else
        old_value + separator + value
      end
    end
  end

  sig { params(keys: T.any(String, T::Array[String]), value: T.untyped, separator: String).void }
  def prepend(keys, value, separator = " ")
    value = value.to_s
    Array(keys).each do |key|
      old_value = self[key]
      self[key] = if old_value.blank?
        value
      else
        value + separator + old_value
      end
    end
  end

  sig { params(key: String, path: T.any(String, Pathname)).void }
  def append_path(key, path)
    self[key] = PATH.new(self[key]).append(path)
  end

  # Prepends a directory to `PATH`.
  # Is the formula struggling to find the pkgconfig file? Point it to it.
  # This is done automatically for keg-only formulae.
  # <pre>ENV.prepend_path "PKG_CONFIG_PATH", "#{Formula["glib"].opt_lib}/pkgconfig"</pre>
  # Prepending a system path such as /usr/bin is a no-op so that requirements
  # don't accidentally override superenv shims or formulae's `bin` directories.
  # <pre>ENV.prepend_path "PATH", which("emacs").dirname</pre>
  sig { params(key: String, path: T.any(String, Pathname)).void }
  def prepend_path(key, path)
    return if %w[/usr/bin /bin /usr/sbin /sbin].include? path.to_s

    self[key] = PATH.new(self[key]).prepend(path)
  end

  sig { params(key: String, path: T.any(String, Pathname)).void }
  def prepend_create_path(key, path)
    path = Pathname(path)
    path.mkpath
    prepend_path key, path
  end

  sig { params(keys: T.any(String, T::Array[String]), value: T.untyped).void }
  def remove(keys, value)
    return if value.nil?

    Array(keys).each do |key|
      old_value = self[key]
      next if old_value.nil?

      new_value = old_value.sub(value, "")
      if new_value.empty?
        delete(key)
      else
        self[key] = new_value
      end
    end
  end

  sig { returns(T.nilable(String)) }
  def cc
    self["CC"]
  end

  sig { returns(T.nilable(String)) }
  def cxx
    self["CXX"]
  end

  sig { returns(T.nilable(String)) }
  def cflags
    self["CFLAGS"]
  end

  sig { returns(T.nilable(String)) }
  def cxxflags
    self["CXXFLAGS"]
  end

  sig { returns(T.nilable(String)) }
  def cppflags
    self["CPPFLAGS"]
  end

  sig { returns(T.nilable(String)) }
  def ldflags
    self["LDFLAGS"]
  end

  sig { returns(T.nilable(String)) }
  def fc
    self["FC"]
  end

  sig { returns(T.nilable(String)) }
  def fflags
    self["FFLAGS"]
  end

  sig { returns(T.nilable(String)) }
  def fcflags
    self["FCFLAGS"]
  end

  # Outputs the current compiler.
  # <pre># Do something only for the system clang
  # if ENV.compiler == :clang
  #   # modify CFLAGS CXXFLAGS OBJCFLAGS OBJCXXFLAGS in one go:
  #   ENV.append_to_cflags "-I ./missing/includes"
  # end</pre>
  sig { returns(T.any(Symbol, String)) }
  def compiler
    @compiler ||= if (cc = @cc)
      warn_about_non_apple_gcc(cc) if cc.match?(GNU_GCC_REGEXP)

      fetch_compiler(cc, "--cc")
    elsif (cc = homebrew_cc)
      warn_about_non_apple_gcc(cc) if cc.match?(GNU_GCC_REGEXP)

      compiler = fetch_compiler(cc, "HOMEBREW_CC")

      if @formula
        compilers = [compiler] + CompilerSelector.compilers
        compiler = CompilerSelector.select_for(@formula, compilers)
      end

      compiler
    elsif @formula
      CompilerSelector.select_for(@formula)
    else
      DevelopmentTools.default_compiler
    end
  end

  sig { returns(T.any(String, Pathname)) }
  def determine_cc
    COMPILER_SYMBOL_MAP.invert.fetch(compiler, compiler)
  end
  private :determine_cc

  COMPILERS.each do |compiler|
    define_method(compiler) do
      @compiler = compiler

      send(:cc=, send(:determine_cc))
      send(:cxx=, send(:determine_cxx))
    end
  end

  sig { void }
  def fortran
    # Ignore repeated calls to this function as it will misleadingly warn about
    # building with an alternative Fortran compiler without optimization flags,
    # despite it often being the Homebrew-provided one set up in the first call.
    return if @fortran_setup_done

    @fortran_setup_done = true

    flags = []

    if fc
      ohai "Building with an alternative Fortran compiler", "This is unsupported."
      self["F77"] ||= fc
    else
      if (gfortran = which("gfortran", (HOMEBREW_PREFIX/"bin").to_s))
        ohai "Using Homebrew-provided Fortran compiler"
      elsif (gfortran = which("gfortran", PATH.new(ORIGINAL_PATHS)))
        ohai "Using a Fortran compiler found at #{gfortran}"
      end
      if gfortran
        puts "This may be changed by setting the FC environment variable."
        self["FC"] = self["F77"] = gfortran
        flags = FC_FLAG_VARS
      end
    end

    flags.each { |key| self[key] = cflags }
    set_cpu_flags(flags)
  end

  # @private
  sig { returns(Symbol) }
  def effective_arch
    if @build_bottle && @bottle_arch
      @bottle_arch.to_sym
    else
      Hardware.oldest_cpu
    end
  end

  # @private
  sig { params(name: String).returns(Formula) }
  def gcc_version_formula(name)
    version = name[GNU_GCC_REGEXP, 1]
    gcc_version_name = "gcc@#{version}"

    gcc = Formulary.factory("gcc")
    if gcc.respond_to?(:version_suffix) && T.unsafe(gcc).version_suffix == version
      gcc
    else
      Formulary.factory(gcc_version_name)
    end
  end

  # @private
  sig { params(name: String).void }
  def warn_about_non_apple_gcc(name)
    begin
      gcc_formula = gcc_version_formula(name)
    rescue FormulaUnavailableError => e
      raise <<~EOS
        Homebrew GCC requested, but formula #{e.name} not found!
      EOS
    end

    return if gcc_formula.opt_prefix.exist?

    raise <<~EOS
      The requested Homebrew GCC was not installed. You must:
        brew install #{gcc_formula.full_name}
    EOS
  end

  sig { void }
  def permit_arch_flags; end

  # @private
  sig { params(cc: T.any(Symbol, String)).returns(T::Boolean) }
  def compiler_any_clang?(cc = compiler)
    %w[clang llvm_clang].include?(cc.to_s)
  end

  private

  sig { params(_flags: T::Array[String], _map: T::Hash[Symbol, String]).void }
  def set_cpu_flags(_flags, _map = {}); end

  sig { params(val: T.any(String, Pathname)).returns(String) }
  def cc=(val)
    self["CC"] = self["OBJC"] = val.to_s
  end

  sig { params(val: T.any(String, Pathname)).returns(String) }
  def cxx=(val)
    self["CXX"] = self["OBJCXX"] = val.to_s
  end

  sig { returns(T.nilable(String)) }
  def homebrew_cc
    self["HOMEBREW_CC"]
  end

  sig { params(value: String, source: String).returns(Symbol) }
  def fetch_compiler(value, source)
    COMPILER_SYMBOL_MAP.fetch(value) do |other|
      case other
      when GNU_GCC_REGEXP
        other.to_sym
      else
        raise "Invalid value for #{source}: #{other}"
      end
    end
  end

  sig { void }
  def check_for_compiler_universal_support
    raise "Non-Apple GCC can't build universal binaries" if homebrew_cc&.match?(GNU_GCC_REGEXP)
  end
end

require "extend/os/extend/ENV/shared"
