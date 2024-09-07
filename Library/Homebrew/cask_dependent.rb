# typed: true # rubocop:todo Sorbet/StrictSigil
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

  attr_reader :cask

  def initialize(cask)
    @cask = cask
  end

  def name
    @cask.token
  end

  def full_name
    @cask.full_name
  end

  def runtime_dependencies
    deps.flat_map { |dep| [dep, *dep.to_formula.runtime_dependencies] }.uniq
  end

  def deps
    @deps ||= @cask.depends_on.formula.map do |f|
      Dependency.new f
    end
  end

  def requirements
    @requirements ||= begin
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
    end
  end

  def recursive_dependencies(&block)
    Dependency.expand(self, &block)
  end

  def recursive_requirements(&block)
    Requirement.expand(self, &block)
  end

  def any_version_installed?
    @cask.installed?
  end
end
