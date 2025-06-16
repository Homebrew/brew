# typed: strict
# frozen_string_literal: true

require "requirement"

# An adapter for casks to provide dependency information in a formula-like interface.
class CaskDependent
  # Defines a dependency on another cask
  class Requirement < ::Requirement
    satisfy(build_env: false) do
      Cask::CaskLoader.load(cask).installed?
    end
  end

  sig { returns(Cask::Cask) }
  attr_reader :cask

  sig { params(cask: Cask::Cask).void }
  def initialize(cask)
    @cask = T.let(cask, Cask::Cask)
  end

  sig { returns(String) }
  def name
    @cask.token
  end

  sig { returns(String) }
  def full_name
    @cask.full_name
  end

  sig { returns(T::Array[Dependency]) }
  def runtime_dependencies
    deps.flat_map { |dep| [dep, *dep.to_formula.runtime_dependencies] }.uniq
  end

  sig { returns(T::Array[Dependency]) }
  def deps
    @deps ||= T.let(
      @cask.depends_on.formula.map do |f|
        Dependency.new f
      end,
      T.nilable(T::Array[Dependency]),
    )
  end

  sig { returns(T::Array[CaskDependent::Requirement]) }
  def requirements
    @requirements ||= T.let(
      begin
        requirements = []
        dsl_reqs = @cask.depends_on

        dsl_reqs.arch&.each do |arch|
          arch = if arch[:bits] == 64
            if arch[:type] == :intel
              :x86_64
            else
              :"#{arch[:type]}64"
            end
          elsif arch[:type] == :intel && arch[:bits] == 32
            :i386
          else
            arch[:type]
          end
          requirements << ArchRequirement.new([arch])
        end
        dsl_reqs.cask.each do |cask_ref|
          requirements << CaskDependent::Requirement.new([{ cask: cask_ref }])
        end
        requirements << dsl_reqs.macos if dsl_reqs.macos

        requirements
      end,
      T.nilable(T::Array[CaskDependent::Requirement]),
    )
  end

  sig { params(block: T.nilable(T.proc.returns(T::Array[Dependency]))).returns(T::Array[Dependency]) }
  def recursive_dependencies(&block)
    Dependency.expand(self, &block)
  end

  sig { params(block: T.nilable(T.proc.returns(CaskDependent::Requirement))).returns(Requirements) }
  def recursive_requirements(&block)
    Requirement.expand(self, &block)
  end

  sig { returns(T::Boolean) }
  def any_version_installed?
    @cask.installed?
  end
end
