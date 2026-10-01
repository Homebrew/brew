# typed: strict
# frozen_string_literal: true

module Singleton
  # Singleton instances are not duplicable:
  #
  # ```ruby
  # Class.new.include(Singleton).instance.dup # TypeError (can't dup instance of singleton
  # ```
  sig { returns(FalseClass) }
  def duplicable? = false
end
