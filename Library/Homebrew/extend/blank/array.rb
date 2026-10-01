# typed: strict
# frozen_string_literal: true

class Array
  # An array is blank if it's empty:
  #
  # ```ruby
  # [].blank?      # => true
  # [1,2,3].blank? # => false
  # ```
  sig { returns(T::Boolean) }
  def blank? = empty?

  sig { returns(T::Boolean) }
  def present? = !empty? # :nodoc:
end
