# typed: strict
# frozen_string_literal: true

class Time # :nodoc:
  # No Time is blank:
  #
  # ```ruby
  # Time.now.blank? # => false
  # ```
  sig { returns(FalseClass) }
  def blank? = false

  sig { returns(TrueClass) }
  def present? = true
end
