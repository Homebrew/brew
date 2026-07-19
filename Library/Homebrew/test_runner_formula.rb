# typed: strict
# frozen_string_literal: true

require "formula"

class TestRunnerFormula
  sig { returns(String) }
  attr_reader :name

  sig { returns(Formula) }
  attr_reader :formula

  sig { returns(T::Boolean) }
  attr_reader :eval_all

  sig { params(formula: Formula, eval_all: T::Boolean).void }
  def initialize(formula, eval_all: false)
    Formulary.enable_factory_cache!
    @formula = formula
    @name = T.let(formula.name, String)
    @dependent_hash = T.let({}, T::Hash[Symbol, T::Array[TestRunnerFormula]])
    @eval_all = eval_all
    freeze
  end

  sig { returns(T::Boolean) }
  def macos_compatible?
    formula.supports_macos?
  end

  sig { returns(T::Boolean) }
  def linux_compatible?
    formula.supports_linux?
  end

  sig { returns(T::Boolean) }
  def x86_64_only?
    formula.requirements.any? { |r| r.is_a?(ArchRequirement) && (r.arch == :x86_64) }
  end

  # @api internal
  sig { returns(T::Boolean) }
  def x86_64_compatible?
    !arm64_only?
  end

  sig { returns(T::Boolean) }
  def arm64_only?
    formula.requirements.any? { |r| r.is_a?(ArchRequirement) && (r.arch == :arm64) }
  end

  # @api internal
  sig { returns(T::Boolean) }
  def arm64_compatible?
    !x86_64_only?
  end

  sig { returns(T.nilable(MacOSRequirement)) }
  def versioned_macos_requirement
    formula.requirements.find { |r| r.is_a?(MacOSRequirement) && r.version_specified? }
  end

  sig { params(macos_version: MacOSVersion).returns(T::Boolean) }
  def compatible_with?(macos_version)
    # Assign to a variable to assist type-checking.
    requirement = versioned_macos_requirement
    return true if requirement.blank?

    macos_version.public_send(requirement.comparator, requirement.version)
  end

  sig {
    params(
      platform:      Symbol,
      arch:          Symbol,
      macos_version: T.nilable(Symbol),
    ).returns(T::Array[TestRunnerFormula])
  }
  def dependents(platform:, arch:, macos_version:)
    cache_key = :"#{platform}_#{arch}_#{macos_version}"

    @dependent_hash[cache_key] ||= begin
      os = macos_version || platform
      arch = Homebrew::SimulateSystem.arch_symbols.fetch(arch)

      Homebrew::SimulateSystem.with(os:, arch:) do
        (eval_all ? Formula.all(eval_all: true) : Formula.installed)
          .select { |candidate_f| candidate_f.deps.map(&:name).include?(name) }
          .map { |f| TestRunnerFormula.new(f, eval_all:) }
          .freeze
      end
    end

    @dependent_hash.fetch(cache_key)
  end
end
