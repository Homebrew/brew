# typed: strict
# frozen_string_literal: true

require "options"

# Shared functions for classes which can be depended upon.
module Dependable
  extend T::Helpers

  # Return from an {Dependency.expand} or {Requirement.expand} block to remove
  # a dependency/requirement and all of its recursive dependencies from the result list.
  PRUNE = :prune
  # Return from a {Dependency.expand} block to omit a dependency from the result
  # list but continue expanding its children.
  SKIP = :skip
  # Return from a {Dependency.expand} block to keep a dependency in the result
  # list but stop recursing into its own dependencies.
  KEEP_BUT_PRUNE_RECURSIVE_DEPS = :keep_but_prune_recursive_deps

  # `:run` and `:linked` are no longer used but keep them here to avoid their
  # misuse in future.
  RESERVED_TAGS = T.let(
    [:build, :optional, :recommended, :run, :test, :linked, :implicit, :no_linkage].freeze,
    T::Array[Symbol],
  )

  abstract!

  requires_ancestor { Kernel }

  sig { returns(T::Array[T.any(Symbol, String, T::Array[T.untyped])]) }
  def tags
    @tags ||= T.let([], T.nilable(T::Array[T.any(Symbol, String, T::Array[T.untyped])]))
  end

  sig { abstract.returns(T::Array[String]) }
  def option_names; end

  sig { returns(T::Boolean) }
  def build?
    tags.include? :build
  end

  sig { returns(T::Boolean) }
  def optional?
    tags.include? :optional
  end

  sig { returns(T::Boolean) }
  def recommended?
    tags.include? :recommended
  end

  sig { returns(T::Boolean) }
  def test?
    tags.include? :test
  end

  sig { returns(T::Boolean) }
  def implicit?
    tags.include? :implicit
  end

  sig { returns(T::Boolean) }
  def no_linkage?
    tags.include? :no_linkage
  end

  sig { returns(T::Boolean) }
  def required?
    !build? && !test? && !optional? && !recommended?
  end

  sig { returns(T::Array[String]) }
  def option_tags
    tags.grep(String)
  end

  sig { returns(Options) }
  def options
    Options.create(option_tags)
  end

  sig { params(build: BuildOptions).returns(T::Boolean) }
  def prune_from_option?(build)
    return false if !optional? && !recommended?

    build.without?(self)
  end

  sig { params(dependent: T.any(Formula, Dependency), formula: T.nilable(Formula)).returns(T::Boolean) }
  def prune_if_build_and_not_dependent?(dependent, formula = nil)
    return false unless build?

    if formula
      dependent != formula
    else
      raise "dependent is not a formula or cask dependent" unless dependent.is_a?(Dependency)

      dependent.installed?
    end
  end
end
