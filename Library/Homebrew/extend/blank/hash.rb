# typed: strict
# frozen_string_literal: true

class Hash
  # A hash is blank if it's empty:
  #
  #
  # ```ruby
  # {}.blank?                # => true
  # { key: 'value' }.blank?  # => false
  # ```
  sig { returns(T::Boolean) }
  def blank? = empty?

  sig { returns(T::Boolean) }
  def present? = !empty? # :nodoc:
end
