# typed: strict
# frozen_string_literal: true

require "cask_dependent"

# Helper functions for dependencies.
module DependenciesHelpers
  def args_includes_ignores(args)
    includes = [:required?, :recommended?] # included by default
    includes << :implicit? if args.include_implicit?
    includes << :build? if args.include_build?
    includes << :test? if args.include_test?
    includes << :optional? if args.include_optional?

    ignores = []
    ignores << :recommended? if args.skip_recommended?
    ignores << :satisfied? if args.missing?

    [includes, ignores]
  end

  sig {
    params(root_dependent: T.any(Formula, CaskDependent), includes: T::Array[Symbol], ignores: T::Array[Symbol])
      .returns(T::Array[Dependency])
  }
  def recursive_dep_includes(root_dependent, includes, ignores)
    T.cast(recursive_includes(Dependency, root_dependent, includes, ignores), T::Array[Dependency])
  end

  sig {
    params(root_dependent: T.any(Formula, CaskDependent), includes: T::Array[Symbol], ignores: T::Array[Symbol])
      .returns(Requirements)
  }
  def recursive_req_includes(root_dependent, includes, ignores)
    T.cast(recursive_includes(Requirement, root_dependent, includes, ignores), Requirements)
  end

  sig {
    params(
      klass:          T.any(T.class_of(Dependency), T.class_of(Requirement)),
      root_dependent: T.any(Formula, CaskDependent),
      includes:       T::Array[Symbol],
      ignores:        T::Array[Symbol],
    ).returns(T.any(T::Array[Dependency], Requirements))
  }
  def recursive_includes(klass, root_dependent, includes, ignores)
    cache_key = "recursive_includes_#{includes}_#{ignores}"

    klass.expand(root_dependent, cache_key:) do |dependent, dep|
      next Dependable::PRUNE if ignores.any? { |ignore| dep.public_send(ignore) }
      next Dependable::PRUNE if includes.none? do |include|
        # Ignore indirect test dependencies
        next if include == :test? && dependent != root_dependent

        dep.public_send(include)
      end

      # If a tap isn't installed, we can't find the dependencies of one of
      # its formulae and an exception will be thrown if we try.
      next Dependable::KEEP_BUT_PRUNE_RECURSIVE_DEPS if klass == Dependency && (tap = dep.tap) && !tap.installed?
    end
  end

  sig {
    params(
      dependables: T.any(Dependencies, Requirements, T::Array[Dependency], T::Array[Requirement]),
      ignores:     T::Array[Symbol],
      includes:    T::Array[Symbol],
    ).returns(T::Array[T.any(Dependency, Requirement)])
  }
  def select_includes(dependables, ignores, includes)
    dependables.select do |dep|
      next false if ignores.any? { |ignore| dep.public_send(ignore) }

      includes.any? { |include| dep.public_send(include) }
    end
  end

  sig {
    params(formulae_or_casks: T::Array[T.any(Formula, Keg, Cask::Cask)])
      .returns(T::Array[T.any(Formula, CaskDependent)])
  }
  def dependents(formulae_or_casks)
    formulae_or_casks.map do |formula_or_cask|
      case formula_or_cask
      when Formula then formula_or_cask
      when Cask::Cask then CaskDependent.new(formula_or_cask)
      else
        raise TypeError, "Unsupported type: #{formula_or_cask.class}"
      end
    end
  end
end
