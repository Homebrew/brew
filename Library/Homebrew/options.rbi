# typed: strict

class Options
  # This is a workaround to enable `alias to_ary to_a`
  # @see https://github.com/sorbet/sorbet/issues/2378#issuecomment-569474238
  sig { returns(T::Array[Option]) }
  def to_a; end
end
