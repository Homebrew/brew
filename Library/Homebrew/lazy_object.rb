# typed: strict
# frozen_string_literal: true

require "delegate"

# An object which lazily evaluates its inner block only once a method is called on it.
class LazyObject < Delegator
  sig { params(callable: T.nilable(Proc)).void }
  def initialize(&callable)
    @__callable__ = T.let(nil, T.nilable(Proc))
    @getobj_set = T.let(false, T::Boolean)
    @__getobj__ = T.let(nil, T.untyped)
    super(callable)
  end

  sig { params(_blk: T.untyped).returns(T.untyped) }
  def __getobj__(&_blk)
    return @__getobj__ if @getobj_set

    @__getobj__ = T.must(@__callable__).call
    @getobj_set = true
    @__getobj__
  end

  sig { params(callable: T.nilable(Proc)).void }
  def __setobj__(callable)
    @__callable__ = callable
    @getobj_set = false
    @__getobj__ = nil
  end

  # Forward to the inner object to make lazy objects type-checkable.
  #
  # @!visibility private
  sig { params(klass: T.any(T::Module[T.anything], T::Class[T.anything])).returns(T::Boolean) }
  def is_a?(klass)
    # see https://sorbet.org/docs/faq#how-can-i-fix-type-errors-that-arise-from-super
    T.bind(self, T.untyped)

    __getobj__.is_a?(klass) || super
  end

  sig { returns(T::Class[T.anything]) }
  def class = __getobj__.class

  sig { returns(String) }
  def to_s = __getobj__.to_s
end
