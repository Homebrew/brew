# typed: strict
# frozen_string_literal: true

class FalseClass
  # `false` is blank:
  #
  # ```ruby
  # false.blank? # => true
  # ```
  sig { returns(TrueClass) }
  def blank? = true

  sig { returns(FalseClass) }
  def present? = false # :nodoc:
end
