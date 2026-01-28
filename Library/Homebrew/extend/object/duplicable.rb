# typed: strict
# frozen_string_literal: true

# Most objects are cloneable, but not all. For example you can't dup methods:
#
# ```ruby
# method(:puts).dup # => TypeError: allocator undefined for Method
# ```
#
# Classes may signal their instances are not duplicable removing +dup+/+clone+
# or raising exceptions from them. So, to dup an arbitrary object you normally
# use an optimistic approach and are ready to catch an exception, say:
#
# ```ruby
# arbitrary_object.dup rescue object
# ```
#
# Rails dups objects in a few critical spots where they are not that arbitrary.
# That `rescue` is very expensive (like 40 times slower than a predicate) and it
# is often triggered.
#
# That's why we hardcode the following cases and check duplicable? instead of
# using that rescue idiom.
# rubocop:disable Layout/EmptyLines


# rubocop:enable Layout/EmptyLines
class Object
  # Can you safely dup this object?
  #
  # False for method objects;
  # true otherwise.
  sig { returns(T::Boolean) }
  def duplicable? = true
end

class Method
  # Methods are not duplicable:
  #
  # ```ruby
  # method(:puts).duplicable? # => false
  # method(:puts).dup         # => TypeError: allocator undefined for Method
  # ```
  sig { returns(FalseClass) }
  def duplicable? = false
end

class UnboundMethod
  # Unbound methods are not duplicable:
  #
  # ```ruby
  # method(:puts).unbind.duplicable? # => false
  # method(:puts).unbind.dup         # => TypeError: allocator undefined for UnboundMethod
  # ```
  sig { returns(FalseClass) }
  def duplicable? = false
end

require "singleton"

module Singleton
  # Singleton instances are not duplicable:
  #
  # ```ruby
  # Class.new.include(Singleton).instance.dup # TypeError (can't dup instance of singleton
  # ```
  sig { returns(FalseClass) }
  def duplicable? = false
end
