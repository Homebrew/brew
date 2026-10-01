# typed: strict
# frozen_string_literal: true

class Array
  # Equal to `self[1]`.
  #
  # ### Example
  #
  # ```ruby
  # %w( a b c d e ).second # => "b"
  # ```
  def second = self[1]

  # Equal to `self[2]`.
  #
  # ### Example
  #
  # ```ruby
  # %w( a b c d e ).third # => "c"
  # ```
  def third = self[2]

  # Equal to `self[3]`.
  #
  # ### Example
  #
  # ```ruby
  # %w( a b c d e ).fourth # => "d"
  # ```
  def fourth = self[3]

  # Equal to `self[4]`.
  #
  # ### Example
  #
  # ```ruby
  # %w( a b c d e ).fifth # => "e"
  # ```
  def fifth = self[4]
end
