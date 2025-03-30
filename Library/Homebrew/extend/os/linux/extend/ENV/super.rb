# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Superenv
  sig { returns(Pathname) }
  def self.shims_path
    HOMEBREW_SHIMS_PATH/"linux/super"
  end

  sig { returns(T.nilable(Pathname)) }
  def self.bin
    shims_path.realpath
  end

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
    generic_setup_build_environment(formula:, cc:, build_bottle:, bottle_arch:,
                                    testing_formula:, debug_symbols:)
    self["HOMEBREW_OPTIMIZATION_LEVEL"] = "O2"
    self["HOMEBREW_DYNAMIC_LINKER"] = determine_dynamic_linker_path
    self["HOMEBREW_RPATH_PATHS"] = determine_rpath_paths(@formula)
    m4_path_deps = ["libtool", "bison"]
    self["M4"] = "#{HOMEBREW_PREFIX}/opt/m4/bin/m4" if deps.any? { m4_path_deps.include?(_1.name) }

    # Pointer authentication and BTI are hardening techniques most distros
    # use by default on their packages. arm64 Linux we're packaging
    # everything from scratch so the entire dependency tree can have it.
    append_to_cccfg "b" if Hardware::CPU.arch == :arm64 && DevelopmentTools.gcc_version("gcc") >= 9
  end

  def homebrew_extra_paths
    paths = generic_homebrew_extra_paths
    paths += %w[binutils make].filter_map do |f|
      bin = Formulary.factory(f).opt_bin
      bin if bin.directory?
    rescue FormulaUnavailableError
      nil
    end
    paths
  end

  def homebrew_extra_isystem_paths
    paths = []
    # Add paths for GCC headers when building against versioned glibc because we have to use -nostdinc.
    if deps.any? { |d| d.name.match?(/^glibc@.+$/) }
      gcc_include_dir = Utils.safe_popen_read(cc, "--print-file-name=include").chomp
      gcc_include_fixed_dir = Utils.safe_popen_read(cc, "--print-file-name=include-fixed").chomp
      paths << gcc_include_dir << gcc_include_fixed_dir
    end
    paths
  end

  def determine_rpath_paths(formula)
    PATH.new(
      *formula&.lib,
      "#{HOMEBREW_PREFIX}/opt/gcc/lib/gcc/current",
      PATH.new(run_time_deps.map { |dep| dep.opt_lib.to_s }).existing,
      "#{HOMEBREW_PREFIX}/lib",
    )
  end

  sig { returns(T.nilable(String)) }
  def determine_dynamic_linker_path
    path = "#{HOMEBREW_PREFIX}/lib/ld.so"
    return unless File.readable? path

    path
  end
end
