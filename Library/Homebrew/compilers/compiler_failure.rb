# typed: strict
# frozen_string_literal: true

# Class for checking compiler compatibility for a formula.
class CompilerFailure
  sig { returns(Symbol) }
  attr_reader :type

  sig { params(val: T.nilable(T.any(Integer, String))).returns(Version) }
  def version(val = nil)
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
    params(
      spec:  T.any(Symbol, T::Hash[Symbol, String]),
      block: T.nilable(T.proc.bind(CompilerFailure).void),
    ).returns(
      T.attached_class,
    )
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
      block:             T.nilable(T.proc.bind(CompilerFailure).void),
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
