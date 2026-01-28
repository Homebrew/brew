# typed: strict
# frozen_string_literal: true

module CompilerConstants
  # GCC 7 - Ubuntu 18.04 (ESM ends 2028-04-01)
  # GCC 8 - RHEL 8       (ELS ends 2032-05-31)
  GNU_GCC_VERSIONS = %w[7 8 9 10 11 12 13 14 15].freeze
  GNU_GCC_REGEXP = /^gcc-(#{GNU_GCC_VERSIONS.join("|")})$/
  COMPILER_SYMBOL_MAP = T.let({
    "gcc"        => :gcc,
    "clang"      => :clang,
    "llvm_clang" => :llvm_clang,
  }.freeze, T::Hash[String, Symbol])

  COMPILERS = T.let((COMPILER_SYMBOL_MAP.values +
                     GNU_GCC_VERSIONS.map { |n| "gcc-#{n}" }).freeze, T::Array[T.any(String, Symbol)])
end

# Class for checking compiler compatibility for a formula.
class CompilerFailure
  sig { returns(Symbol) }
  attr_reader :type

  sig { params(val: T.any(Integer, String)).returns(Version) }
  def version(val = T.unsafe(nil))
    @version = Version.parse(val.to_s) if val
    @version
  end

  # Allows Apple compiler `fails_with` statements to keep using `build`
  # even though `build` and `version` are the same internally.
  alias build version

  # The cause is no longer used so we need not hold a reference to the string.
  sig { params(_: String).void }
  def cause(_); end

  sig {
    params(spec: T.any(Symbol, T::Hash[Symbol, String]), block: T.nilable(T.proc.void)).returns(T.attached_class)
  }
  def self.create(spec, &block)
    # Non-Apple compilers are in the format fails_with compiler => version
    if spec.is_a?(Hash)
      compiler, major_version = spec.first
      raise ArgumentError, "The `fails_with` hash syntax only supports GCC" if compiler != :gcc

      type = compiler
      # so `fails_with gcc: "7"` simply marks all 7 releases incompatible
      version = "#{major_version}.999"
      exact_major_match = true
    else
      type = spec
      version = 9999
      exact_major_match = false
    end
    new(type, version, exact_major_match:, &block)
  end

  sig { params(compiler: CompilerSelector::Compiler).returns(T::Boolean) }
  def fails_with?(compiler)
    version_matched = if type != :gcc
      version >= compiler.version
    elsif @exact_major_match
      gcc_major(version) == gcc_major(compiler.version) && version >= compiler.version
    else
      gcc_major(version) >= gcc_major(compiler.version)
    end
    type == compiler.type && version_matched
  end

  sig { returns(String) }
  def inspect
    "#<#{self.class.name}: #{type} #{version}>"
  end

  private

  sig {
    params(
      type:              Symbol,
      version:           T.any(Integer, String),
      exact_major_match: T::Boolean,
      block:             T.nilable(T.proc.void),
    ).void
  }
  def initialize(type, version, exact_major_match:, &block)
    @type = type
    @version = T.let(Version.parse(version.to_s), Version)
    @exact_major_match = exact_major_match
    instance_eval(&block) if block
  end

  sig { params(version: Version).returns(Version) }
  def gcc_major(version)
    Version.new(version.major.to_s)
  end
end

# Class for selecting a compiler for a formula.
class CompilerSelector
  include CompilerConstants

  class Compiler < T::Struct
    const :type, Symbol
    const :name, T.any(String, Symbol)
    const :version, Version
  end

  COMPILER_PRIORITY = T.let({
    clang: [:clang, :llvm_clang, :gnu],
    gcc:   [:gnu, :gcc, :llvm_clang, :clang],
  }.freeze, T::Hash[Symbol, T::Array[Symbol]])

  sig {
    params(formula: T.any(Formula, SoftwareSpec), compilers: T.nilable(T::Array[Symbol]), testing_formula: T::Boolean)
      .returns(T.any(String, Symbol))
  }
  def self.select_for(formula, compilers = nil, testing_formula: false)
    if compilers.nil? && DevelopmentTools.default_compiler == :clang
      deps = formula.deps.filter_map do |dep|
        dep.name if dep.required? || (testing_formula && dep.test?) || (!testing_formula && dep.build?)
      end
      compilers = [:clang, :gnu, :llvm_clang] if deps.none?("llvm") && deps.any?(/^gcc(@\d+)?$/)
    end
    new(formula, DevelopmentTools, compilers || self.compilers).compiler
  end

  sig { returns(T::Array[Symbol]) }
  def self.compilers
    COMPILER_PRIORITY.fetch(DevelopmentTools.default_compiler)
  end

  sig { returns(T.any(Formula, SoftwareSpec)) }
  attr_reader :formula

  sig { returns(T::Array[CompilerFailure]) }
  attr_reader :failures

  sig { returns(T.class_of(DevelopmentTools)) }
  attr_reader :versions

  sig { returns(T::Array[Symbol]) }
  attr_reader :compilers

  sig {
    params(
      formula:   T.any(Formula, SoftwareSpec),
      versions:  T.class_of(DevelopmentTools),
      compilers: T::Array[Symbol],
    ).void
  }
  def initialize(formula, versions, compilers)
    @formula = formula
    @failures = T.let(formula.compiler_failures, T::Array[CompilerFailure])
    @versions = versions
    @compilers = compilers
  end

  sig { returns(T.any(String, Symbol)) }
  def compiler
    find_compiler { |c| return c.name unless fails_with?(c) }
    raise CompilerSelectionError, formula
  end

  sig { returns(String) }
  def self.preferred_gcc
    "gcc"
  end

  private

  sig { returns(T::Array[String]) }
  def gnu_gcc_versions
    # prioritize gcc version provided by gcc formula.
    v = Formulary.factory(CompilerSelector.preferred_gcc).version.to_s.slice(/\d+/)
    GNU_GCC_VERSIONS - [v] + [v] # move the version to the end of the list
  rescue FormulaUnavailableError
    GNU_GCC_VERSIONS
  end

  sig { params(_block: T.proc.params(arg0: Compiler).void).void }
  def find_compiler(&_block)
    compilers.each do |compiler|
      case compiler
      when :gnu
        gnu_gcc_versions.reverse_each do |v|
          executable = "gcc-#{v}"
          version = compiler_version(executable)
          yield Compiler.new(type: :gcc, name: executable, version:) unless version.null?
        end
      when :llvm
        next # no-op. DSL supported, compiler is not.
      else
        version = compiler_version(compiler)
        yield Compiler.new(type: compiler, name: compiler, version:) unless version.null?
      end
    end
  end

  sig { params(compiler: Compiler).returns(T::Boolean) }
  def fails_with?(compiler)
    failures.any? { |failure| failure.fails_with?(compiler) }
  end

  sig { params(name: T.any(String, Symbol)).returns(Version) }
  def compiler_version(name)
    case name.to_s
    when "gcc", GNU_GCC_REGEXP
      versions.gcc_version(name.to_s)
    else
      versions.send(:"#{name}_build_version")
    end
  end
end

require "extend/os/compilers"
