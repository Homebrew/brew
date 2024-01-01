# typed: true
# frozen_string_literal: true

require "delegate"

# An object which lazily evaluates its inner block only once a method is called on it.
#
# @api private
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

  def __setobj__(callable)
    @__callable__ = callable
  end

  # Forward to the inner object to make lazy objects type-checkable.
  def is_a?(klass)
    # see https://sorbet.org/docs/faq#how-can-i-fix-type-errors-that-arise-from-super
    T.bind(self, T.untyped)
    __getobj__.is_a?(klass) || super
  end
end
