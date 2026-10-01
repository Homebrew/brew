# typed: strict
# frozen_string_literal: true

class Module
  # Returns a copy of module or class if it's anonymous. If it's
  # named, returns +self+.
  #
  #   Object.deep_dup == Object # => true
  #   klass = Class.new
  #   klass.deep_dup == klass # => false
  sig { returns(T.self_type) }
  def deep_dup
    if name.nil?
      super
    else
      self
    end
  end
end
