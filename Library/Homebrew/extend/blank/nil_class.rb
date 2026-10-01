# typed: strict
# frozen_string_literal: true

class NilClass
  # `nil` is blank:
  #
  # ```ruby
  # nil.blank? # => true
  # ```
  sig { returns(TrueClass) }
  def blank? = true

  sig { returns(FalseClass) }
  def present? = false # :nodoc:
end
