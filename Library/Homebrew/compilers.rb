# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module CompilerConstants
  GNU_GCC_VERSIONS = %w[7 8 9 10 11 12 13 14 15].freeze
  GNU_GCC_REGEXP = /^gcc-(#{GNU_GCC_VERSIONS.join("|")})$/
  COMPILER_SYMBOL_MAP = {
    "gcc"        => :gcc,
    "clang"      => :clang,
    "llvm_clang" => :llvm_clang,
  }.freeze

  COMPILERS = (COMPILER_SYMBOL_MAP.values +
               GNU_GCC_VERSIONS.map { |n| "gcc-#{n}" }).freeze
end

# Class for checking compiler compatibility for a formula.
class CompilerFailure
  attr_reader :type

  def version(val = nil)
    @version = Version.parse(val.to_s) if val
    @version
  end

  # Allows Apple compiler `fails_with` statements to keep using `build`
  # even though `build` and `version` are the same internally.
  alias build version

  # The cause is no longer used so we need not hold a reference to the string.
  def cause(_); end

  def self.for_standard(standard)
    COLLECTIONS.fetch(standard) do
      raise ArgumentError, "\"#{standard}\" is not a recognized standard"
    end
  end

  def self.create(spec, &block)
    # Non-Apple compilers are in the format fails_with compiler => version
    if spec.is_a?(Hash)
      compiler, major_version = spec.first
      raise ArgumentError, "The hash `fails_with` syntax only supports GCC" if compiler != :gcc

      type = compiler
      # so fails_with :gcc => '7' simply marks all 7 releases incompatible
      version = "#{major_version}.999"
      exact_major_match = true
    else
      type = spec
      version = 9999
      exact_major_match = false
    end
    new(type, version, exact_major_match:, &block)
  end

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

  def initialize(type, version, exact_major_match:, &block)
    @type = type
    @version = Version.parse(version.to_s)
    @exact_major_match = exact_major_match
    instance_eval(&block) if block
  end

  def gcc_major(version)
    if version.major >= 5
      Version.new(version.major.to_s)
    else
      version.major_minor
    end
  end

  COLLECTIONS = {
    openmp: [
      create(:clang),
    ],
  }.freeze
  private_constant :COLLECTIONS
end

# Class for selecting a compiler for a formula.
class CompilerSelector
  include CompilerConstants

  Compiler = Struct.new(:type, :name, :version)

  COMPILER_PRIORITY = {
    clang: [:clang, :gnu, :llvm_clang],
    gcc:   [:gnu, :gcc, :llvm_clang, :clang],
  }.freeze

  def self.select_for(formula, compilers = self.compilers)
    new(formula, DevelopmentTools, compilers).compiler
  end

  def self.compilers
    COMPILER_PRIORITY.fetch(DevelopmentTools.default_compiler)
  end

  attr_reader :formula, :failures, :versions, :compilers

  def initialize(formula, versions, compilers)
    @formula = formula
    @failures = formula.compiler_failures
    @versions = versions
    @compilers = compilers
  end

  def compiler
    find_compiler { |c| return c.name unless fails_with?(c) }
    raise CompilerSelectionError, formula
  end

  sig { returns(String) }
  def self.preferred_gcc
    "gcc"
  end

  private

  def gnu_gcc_versions
    # prioritize gcc version provided by gcc formula.
    v = Formulary.factory(CompilerSelector.preferred_gcc).version.to_s.slice(/\d+/)
    GNU_GCC_VERSIONS - [v] + [v] # move the version to the end of the list
  rescue FormulaUnavailableError
    GNU_GCC_VERSIONS
  end

  def find_compiler
    compilers.each do |compiler|
      case compiler
      when :gnu
        gnu_gcc_versions.reverse_each do |v|
          executable = "gcc-#{v}"
          version = compiler_version(executable)
          yield Compiler.new(:gcc, executable, version) unless version.null?
        end
      when :llvm
        next # no-op. DSL supported, compiler is not.
      else
        version = compiler_version(compiler)
        yield Compiler.new(compiler, compiler, version) unless version.null?
      end
    end
  end

  def fails_with?(compiler)
    failures.any? { |failure| failure.fails_with?(compiler) }
  end

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
