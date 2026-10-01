# typed: strict
# frozen_string_literal: true

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
