# typed: strict
# frozen_string_literal: true

require "formula"

class TestRunnerFormula
  sig { returns(String) }
  attr_reader :name

  sig { returns(Formula) }
  attr_reader :formula

  sig { returns(T::Boolean) }
  attr_reader :include_uninstalled

  sig { params(formula: Formula, include_uninstalled: T::Boolean).void }
  def initialize(formula, include_uninstalled: false)
    Formulary.enable_factory_cache!
    @formula = formula
    @name = T.let(formula.name, String)
    @dependent_hash = T.let({}, T::Hash[Symbol, T::Array[TestRunnerFormula]])
    @include_uninstalled = include_uninstalled
    freeze
  end

  sig { returns(T::Boolean) }
  def macos_only?
    !linux_compatible?
  end

  sig { returns(T::Boolean) }
  def macos_compatible?
    formula.supports_macos?
  end

  sig { returns(T::Boolean) }
  def linux_only?
    !macos_compatible?
  end

  sig { returns(T::Boolean) }
  def linux_compatible?
    formula.supports_linux?
  end

  sig { returns(T::Boolean) }
  def x86_64_only?
    formula.requirements.any? { |r| r.is_a?(ArchRequirement) && (r.arch == :x86_64) }
  end

  sig { returns(T::Boolean) }
  def x86_64_compatible?
    !arm64_only?
  end

  sig { returns(T::Boolean) }
  def arm64_only?
    formula.requirements.any? { |r| r.is_a?(ArchRequirement) && (r.arch == :arm64) }
  end

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

  sig { params(platform: Symbol, arch: Symbol, macos_version: T.nilable(MacOSVersion)).returns(T::Boolean) }
  def compatible?(platform:, arch:, macos_version: nil)
    return false if macos_version && !compatible_with?(macos_version)
    return false unless public_send(:"#{platform}_compatible?")

    !!public_send(:"#{arch}_compatible?")
  end

  # Reloads the formula as the runner building `tag` bottles would so its `on_*` blocks apply.
  sig { params(tag: Utils::Bottles::Tag).returns(T::Boolean) }
  def compatible_with_tag?(tag)
    platform = tag.linux? ? :linux : :macos
    arch = tag.standardized_arch
    macos_version = tag.to_macos_version if tag.macos?

    Homebrew::SimulateSystem.with(os: tag.system, arch: Homebrew::SimulateSystem.arch_symbols.fetch(arch)) do
      TestRunnerFormula.new(Formulary.factory(formula.full_name)).compatible?(platform:, arch:, macos_version:)
    end
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
        (include_uninstalled ? Formula.all : Formula.installed)
          .select { |candidate_f| candidate_f.deps.map(&:name).include?(name) }
          .map { |formula| TestRunnerFormula.new(formula, include_uninstalled:) }
          .freeze
      end
    end

    @dependent_hash.fetch(cache_key)
  end
end
