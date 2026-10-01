# typed: strict
# frozen_string_literal: true

class Symbol
  # A Symbol is blank if it's empty:
  #
  # ```ruby
  # :''.blank?     # => true
  # :symbol.blank? # => false
  # ```
  sig { returns(T::Boolean) }
  def blank? = empty?

  sig { returns(T::Boolean) }
  def present? = !empty? # :nodoc:
end
