# typed: strict

class PkgVersion
  # This is a workaround to enable `alias eql? ==`
  # @see https://github.com/sorbet/sorbet/issues/2378#issuecomment-569474238
  sig { params(other: BasicObject).returns(T::Boolean) }
  def ==(other); end
end
