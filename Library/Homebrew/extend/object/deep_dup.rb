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

class Array
  # Returns a deep copy of array.
  #
  #   array = [1, [2, 3]]
  #   dup   = array.deep_dup
  #   dup[1][2] = 4
  #
  #   array[1][2] # => nil
  #   dup[1][2]   # => 4
  sig { returns(T.self_type) }
  def deep_dup
    T.unsafe(self).map(&:deep_dup)
  end
end

class Hash
  # Returns a deep copy of hash.
  #
  #   hash = { a: { b: 'b' } }
  #   dup  = hash.deep_dup
  #   dup[:a][:c] = 'c'
  #
  #   hash[:a][:c] # => nil
  #   dup[:a][:c]  # => "c"
  sig { returns(T.self_type) }
  def deep_dup
    hash = dup
    each_pair do |key, value|
      case key
      when ::String, ::Symbol
        hash[key] = T.unsafe(value).deep_dup
      else
        hash.delete(key)
        hash[T.unsafe(key).deep_dup] = T.unsafe(value).deep_dup
      end
    end
    hash
  end
end

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
