# typed: strict
# frozen_string_literal: true

require "extend/object/duplicable"

class Object
  # Returns a deep copy of object if it's duplicable. If it's
  # not duplicable, returns +self+.
  #
  #   object = Object.new
  #   dup    = object.deep_dup
  #   dup.instance_variable_set(:@a, 1)
  #
  #   object.instance_variable_defined?(:@a) # => false
  #   dup.instance_variable_defined?(:@a)    # => true
  sig { returns(T.self_type) }
  def deep_dup
    duplicable? ? dup : self
  end
end
require "extend/object/deep_dup/array"
require "extend/object/deep_dup/hash"
require "extend/object/deep_dup/module"
