# typed: strict
# frozen_string_literal: true

require "hardware"
require "extend/ENV/shared"

# @api private
module Stdenv
  include SharedEnvExtension

  # @private
  SAFE_CFLAGS_FLAGS = "-w -pipe"

  # @private
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
    super

    self["HOMEBREW_ENV"] = "std"

    ORIGINAL_PATHS.reverse_each { |p| prepend_path "PATH", p }
    prepend_path "PATH", HOMEBREW_SHIMS_PATH/"shared"

    # Set the default pkg-config search path, overriding the built-in paths
    # Anything in PKG_CONFIG_PATH is searched before paths in this variable
    self["PKG_CONFIG_LIBDIR"] = determine_pkg_config_libdir

    self["MAKEFLAGS"] = "-j#{make_jobs}"
    self["RUSTFLAGS"] = Hardware.rustflags_target_cpu

    if HOMEBREW_PREFIX.to_s != "/usr/local"
      # /usr/local is already an -isystem and -L directory so we skip it
      self["CPPFLAGS"] = "-isystem#{HOMEBREW_PREFIX}/include"
      self["LDFLAGS"] = "-L#{HOMEBREW_PREFIX}/lib"
      # CMake ignores the variables above
      self["CMAKE_PREFIX_PATH"] = HOMEBREW_PREFIX.to_s
    end

    frameworks = HOMEBREW_PREFIX.join("Frameworks")
    if frameworks.directory?
      append "CPPFLAGS", "-F#{frameworks}"
      append "LDFLAGS", "-F#{frameworks}"
      self["CMAKE_FRAMEWORK_PATH"] = frameworks.to_s
    end

    # Os is the default Apple uses for all its stuff so let's trust them
    define_cflags "-Os #{SAFE_CFLAGS_FLAGS}"

    begin
      send(compiler)
    rescue CompilerSelectionError
      # We don't care if our compiler fails to build the formula during `brew test`.
      raise unless testing_formula

      send(DevelopmentTools.default_compiler)
    end

    return unless cc&.match?(GNU_GCC_REGEXP)

    gcc_formula = gcc_version_formula(cc)
    append_path "PATH", gcc_formula.opt_bin.to_s
  end
  alias generic_setup_build_environment setup_build_environment

  sig { returns(T::Array[Pathname]) }
  def homebrew_extra_pkg_config_paths
    []
  end

  sig { returns(T.nilable(PATH)) }
  def determine_pkg_config_libdir
    PATH.new(
      HOMEBREW_PREFIX/"lib/pkgconfig",
      HOMEBREW_PREFIX/"share/pkgconfig",
      homebrew_extra_pkg_config_paths,
      "/usr/lib/pkgconfig",
    ).existing
  end

  # Removes the MAKEFLAGS environment variable, causing make to use a single job.
  # This is useful for makefiles with race conditions.
  # When passed a block, MAKEFLAGS is removed only for the duration of the block and is restored after its completion.
  sig { params(block: T.proc.returns(T.untyped)).returns(T.untyped) }
  def deparallelize(&block)
    old = self["MAKEFLAGS"]
    remove "MAKEFLAGS", /-j\d+/
    if block
      begin
        yield
      ensure
        self["MAKEFLAGS"] = old
      end
    end

    old
  end

  %w[O1 O0].each do |opt|
    define_method opt do
      send(:remove_from_cflags, /-O./)
      send(:append_to_cflags, "-#{opt}")
    end
  end

  sig { returns(T.any(String, Pathname)) }
  def determine_cc
    s = super
    DevelopmentTools.locate(s) || Pathname(s)
  end
  private :determine_cc

  sig { returns(Pathname) }
  def determine_cxx
    dir, base = Pathname(determine_cc).split
    dir/base.to_s.sub("gcc", "g++").sub("clang", "clang++")
  end
  private :determine_cxx

  GNU_GCC_VERSIONS.each do |n|
    define_method(:"gcc-#{n}") do
      super()
      send(:set_cpu_cflags)
    end
  end

  sig { void }
  def clang
    super()
    replace_in_cflags(/-Xarch_#{Hardware::CPU.arch_32_bit} (-march=\S*)/, '\1')
    map = Hardware::CPU.optimization_flags.dup
    if DevelopmentTools.clang_build_version < 700
      # Clang mistakenly enables AES-NI on plain Nehalem
      map[:nehalem] = "-march=nehalem -Xclang -target-feature -Xclang -aes"
    end
    set_cpu_cflags(map)
  end

  sig { void }
  def cxx11
    append "CXX", "-std=c++11"
    libcxx
  end

  sig { void }
  def libcxx
    append "CXX", "-stdlib=libc++" if compiler == :clang
  end

  # @private
  sig { params(before: Regexp, after: String).void }
  def replace_in_cflags(before, after)
    CC_FLAG_VARS.each do |key|
      self[key] = fetch(key).sub(before, after) if key?(key)
    end
  end

  # Convenience method to set all C compiler flags in one shot.
  sig { params(val: String).void }
  def define_cflags(val)
    CC_FLAG_VARS.each { |key| self[key] = val }
  end

  # Sets architecture-specific flags for every environment variable
  # given in the list `flags`.
  # @private
  sig { params(flags: T::Array[String], map: T::Hash[Symbol, String]).void }
  def set_cpu_flags(flags, map = Hardware::CPU.optimization_flags)
    cflags =~ /(-Xarch_#{Hardware::CPU.arch_32_bit} )-march=/
    xarch = Regexp.last_match(1).to_s
    remove flags, /(-Xarch_#{Hardware::CPU.arch_32_bit} )?-march=\S*/
    remove flags, /( -Xclang \S+)+/
    remove flags, /-mssse3/
    remove flags, /-msse4(\.\d)?/
    append flags, xarch unless xarch.empty?
    append flags, map.fetch(effective_arch)
  end

  # @private
  sig { params(map: T::Hash[Symbol, String]).void }
  def set_cpu_cflags(map = Hardware::CPU.optimization_flags)
    set_cpu_flags(CC_FLAG_VARS, map)
  end

  sig { returns(Integer) }
  def make_jobs
    Homebrew::EnvConfig.make_jobs.to_i
  end

  # This method does nothing in stdenv since there's no arg refurbishment
  # @private
  sig { void }
  def refurbish_args; end
end

require "extend/os/extend/ENV/std"
