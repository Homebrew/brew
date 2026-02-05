# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "options"

# Shared functions for classes which can be depended upon.
module Dependable
  extend T::Helpers

  # `:run` and `:linked` are no longer used but keep them here to avoid their
  # misuse in future.
  RESERVED_TAGS = [:build, :optional, :recommended, :run, :test, :linked, :implicit, :no_linkage].freeze

  attr_reader :tags

  abstract!

  sig { abstract.returns(T::Array[String]) }
  def option_names; end

  def build?
    tags.include? :build
  end

  def optional?
    tags.include? :optional
  end

  def recommended?
    tags.include? :recommended
  end

  def test?
    tags.include? :test
  end

  def implicit?
    tags.include? :implicit
  end

  def no_linkage?
    tags.include? :no_linkage
  end

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

  def prune_from_option?(build)
    return false if !optional? && !recommended?

    build.without?(self)
  end

  def prune_if_build_and_not_dependent?(dependent, formula = nil)
    return false unless build?
    return dependent.installed? unless formula

    dependent != formula
  end
end
