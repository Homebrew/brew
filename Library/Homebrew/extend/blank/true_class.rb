# typed: strict
# frozen_string_literal: true

class TrueClass
  # `true` is not blank:
  #
  # ```ruby
  # true.blank? # => false
  # ```
  sig { returns(FalseClass) }
  def blank? = false

  sig { returns(TrueClass) }
  def present? = true # :nodoc:
end
