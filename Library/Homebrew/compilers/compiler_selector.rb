# typed: strict
# frozen_string_literal: true

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
      compilers = [:clang, :gnu, :llvm_clang] if deps.none?("llvm") && deps.any?(/^gcc(?:@\d+)?$/)
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
    when "llvm_clang"
      versions.llvm_clang_version
    else
      versions.public_send(:"#{name}_build_version")
    end
  end
end
