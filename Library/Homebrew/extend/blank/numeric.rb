# typed: strict
# frozen_string_literal: true

class Numeric # :nodoc:
  # No number is blank:
  #
  # ```ruby
  # 1.blank? # => false
  # 0.blank? # => false
  # ```
  sig { returns(FalseClass) }
  def blank? = false

  sig { returns(TrueClass) }
  def present? = true
end
