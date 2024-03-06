# typed: true
# frozen_string_literal: true

require "options"

# Shared functions for classes which can be depended upon.
module Dependable
  # `:run` and `:linked` are no longer used but keep them here to avoid their
  # misuse in future.
  RESERVED_TAGS = [:build, :optional, :recommended, :run, :test, :linked, :implicit].freeze

  attr_reader :tags

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

  def required?
    !build? && !test? && !optional? && !recommended?
  end

  def option_tags
    tags - RESERVED_TAGS
  end

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
