# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "delegate"

# An object which lazily evaluates its inner block only once a method is called on it.
class LazyObject < Delegator
  def initialize(&callable)
    super(callable)
  end

  def __getobj__
    # rubocop:disable Naming/MemoizedInstanceVariableName
    return @__delegate__ if defined?(@__delegate__)

    @__delegate__ = @__callable__.call
    # rubocop:enable Naming/MemoizedInstanceVariableName
  end
  private :__getobj__

  def __setobj__(callable)
    @__callable__ = callable
  end
  private :__setobj__

  # Forward to the inner object to make lazy objects type-checkable.
  #
  # @!visibility private
  def is_a?(klass)
    # see https://sorbet.org/docs/faq#how-can-i-fix-type-errors-that-arise-from-super
    T.bind(self, T.untyped)

    __getobj__.is_a?(klass) || super
  end
end
