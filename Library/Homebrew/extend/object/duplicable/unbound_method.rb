# typed: strict
# frozen_string_literal: true

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
