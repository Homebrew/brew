# typed: strict

class Dependencies < SimpleDelegator
  include Enumerable
  include Kernel

  # This is a workaround to enable `alias eql? ==`
  # @see https://github.com/sorbet/sorbet/issues/2378#issuecomment-569474238
  sig { params(other: BasicObject).returns(T::Boolean) }
  def ==(other); end

  sig { params(blk: T.proc.params(arg0: Dependency).void).returns(T.self_type) }
  sig { returns(T::Enumerator[Dependency]) }
  def each(&blk); end

  sig { override.params(blk: T.proc.params(arg0: Dependency).returns(T.anything)).returns(T::Array[Dependency]) }
  sig { override.returns(T::Enumerator[Dependency]) }
  def select(&blk); end
end

class Requirements < SimpleDelegator
  include Enumerable
  include Kernel

  sig { params(blk: T.proc.params(arg0: Requirement).void).returns(T.self_type) }
  sig { returns(T::Enumerator[Requirement]) }
  def each(&blk); end

  sig { override.params(blk: T.proc.params(arg0: Requirement).returns(T.anything)).returns(T::Array[Requirement]) }
  sig { override.returns(T::Enumerator[Requirement]) }
  def select(&blk); end
end
